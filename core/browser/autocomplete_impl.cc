// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include <algorithm>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/feature_list.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/autocomplete/chrome_autocomplete_provider_client.h"
#include "chrome/browser/autocomplete/chrome_autocomplete_scheme_classifier.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "components/omnibox/browser/autocomplete_classifier.h"
#include "components/omnibox/browser/autocomplete_controller.h"
#include "components/omnibox/browser/autocomplete_controller_config.h"
#include "components/omnibox/browser/autocomplete_enums.h"
#include "components/omnibox/browser/autocomplete_input.h"
#include "components/omnibox/browser/autocomplete_match.h"
#include "components/omnibox/browser/autocomplete_match_type.h"
#include "components/omnibox/browser/autocomplete_provider.h"
#include "components/omnibox/browser/autocomplete_result.h"
#include "components/omnibox/common/omnibox_features.h"
#include "oa/browser/profile_services.h"
#include "oa/public/autocomplete.h"
#include "third_party/metrics_proto/omnibox_event.pb.h"
#include "url/gurl.h"

namespace oa {
namespace {

AutocompleteMatch ToMatch(const ::AutocompleteMatch& match) {
  AutocompleteMatch result;
  result.type = omnibox::AutocompleteMatchTypeToString(match.type);
  if (match.provider) {
    result.provider =
        ::AutocompleteProvider::TypeToString(match.provider->type());
  }
  result.contents = base::UTF16ToUTF8(match.contents);
  result.description = base::UTF16ToUTF8(match.description);
  result.destination_url = match.destination_url.spec();
  result.fill_into_edit = base::UTF16ToUTF8(match.fill_into_edit);
  result.inline_autocompletion = base::UTF16ToUTF8(match.inline_autocompletion);
  result.keyword = base::UTF16ToUTF8(match.keyword);
  result.relevance = match.relevance;
  result.allowed_to_be_default = match.allowed_to_be_default_match;
  result.deletable = match.deletable;
  result.swap_contents_and_description = match.swap_contents_and_description;
  result.from_keyword = match.from_keyword;
  result.from_previous = match.from_previous;
  result.additional_info = match.additional_info;
  return result;
}

// As ArcCore's ArcBrowser: upstream's controller with upstream's default
// omnibox providers and config.
class AutocompleteImpl : public Autocomplete,
                         public AutocompleteController::Observer,
                         public ProfileObserver {
 public:
  explicit AutocompleteImpl(const std::string& profile_id) {
    LoadBrowserProfile(profile_id, base::BindOnce(&AutocompleteImpl::Init,
                                                  weak_factory_.GetWeakPtr()));
  }

  ~AutocompleteImpl() override {
    if (controller_) {
      controller_->RemoveObserver(this);
    }
  }

  // Autocomplete:
  void Start(const AutocompleteInput& input, ResultCallback callback) override {
    ++generation_;
    callback_ = std::move(callback);
    if (!controller_) {
      pending_input_ = input;
      return;
    }
    Run(input);
  }

  void Stop() override {
    pending_input_.reset();
    if (controller_) {
      controller_->Stop(AutocompleteStopReason::kInteraction);
    }
  }

  void DeleteMatch(const AutocompleteMatch& match) override {
    if (!controller_) {
      return;
    }
    for (const ::AutocompleteMatch& candidate : controller_->result()) {
      if (omnibox::AutocompleteMatchTypeToString(candidate.type) ==
              match.type &&
          base::UTF16ToUTF8(candidate.contents) == match.contents &&
          candidate.destination_url.spec() == match.destination_url) {
        ::AutocompleteMatch found = candidate;
        controller_->Stop(AutocompleteStopReason::kInteraction);
        controller_->DeleteMatch(found);
        return;
      }
    }
  }

  // AutocompleteController::Observer:
  void OnResultChanged(AutocompleteController* controller,
                       bool default_match_changed) override {
    AutocompleteResult result;
    for (const ::AutocompleteMatch& match : controller->result()) {
      result.combined_matches.push_back(ToMatch(match));
    }
    for (const auto& provider : controller->providers()) {
      for (const ::AutocompleteMatch& match : provider->matches()) {
        result.per_provider_matches.push_back(ToMatch(match));
      }
    }
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(&AutocompleteImpl::Report, weak_factory_.GetWeakPtr(),
                       generation_, std::move(result), controller->done()));
  }

  // ProfileObserver:
  void OnProfileWillBeDestroyed(Profile* profile) override {
    controller_->RemoveObserver(this);
    controller_.reset();
    scheme_classifier_.reset();
    profile_observation_.Reset();
  }

 private:
  void Init(Profile* profile) {
    if (!profile) {
      // The start that waited gets its answer, so the app doesn't wait on it.
      if (std::exchange(pending_input_, std::nullopt)) {
        Report(generation_, AutocompleteResult(), true);
      }
      return;
    }
    profile_observation_.Observe(profile);
    scheme_classifier_ =
        std::make_unique<ChromeAutocompleteSchemeClassifier>(profile);
    AutocompleteControllerConfig config;
    config.provider_types = AutocompleteClassifier::DefaultOmniboxProviders();
    controller_ = std::make_unique<AutocompleteController>(
        std::make_unique<ChromeAutocompleteProviderClient>(profile), config);
    controller_->AddObserver(this);
    if (std::optional<AutocompleteInput> input =
            std::exchange(pending_input_, std::nullopt)) {
      Run(*input);
    }
  }

  void Run(const AutocompleteInput& input) {
    std::u16string text = base::UTF8ToUTF16(input.text);
    size_t cursor_position = std::min(input.cursor_position, text.length());
    if (!input.keyword.empty()) {
      const std::u16string prefix = base::UTF8ToUTF16(input.keyword) + u" ";
      text = prefix + text;
      cursor_position += prefix.length();
    }
    if (input.start_fresh) {
      controller_->ResetSession();
    }
    ::AutocompleteInput chromium_input(
        text, cursor_position, metrics::OmniboxEventProto::OTHER,
        *scheme_classifier_,
        base::FeatureList::IsEnabled(omnibox::kDefaultTypedNavigationsToHttps));
    if (!input.current_url.empty()) {
      chromium_input.set_current_url(GURL(input.current_url));
    }
    chromium_input.set_prevent_inline_autocomplete(
        input.prevent_inline_autocomplete);
    chromium_input.set_in_keyword_mode(!input.keyword.empty());
    chromium_input.set_allow_exact_keyword_match(!input.keyword.empty());
    controller_->Start(chromium_input);
  }

  void Report(int generation, AutocompleteResult result, bool done) {
    if (generation == generation_ && callback_) {
      callback_(result, done);
    }
  }

  int generation_ = 0;
  ResultCallback callback_;
  // A start made before the profile loaded, which Init runs.
  std::optional<AutocompleteInput> pending_input_;
  std::unique_ptr<ChromeAutocompleteSchemeClassifier> scheme_classifier_;
  std::unique_ptr<AutocompleteController> controller_;
  base::ScopedObservation<Profile, ProfileObserver> profile_observation_{this};
  base::WeakPtrFactory<AutocompleteImpl> weak_factory_{this};
};

}  // namespace

std::unique_ptr<Autocomplete> CreateAutocomplete(
    const std::string& profile_id) {
  return std::make_unique<AutocompleteImpl>(profile_id);
}

}  // namespace oa
