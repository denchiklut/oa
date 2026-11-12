// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_PUBLIC_AUTOCOMPLETE_H_
#define OA_PUBLIC_AUTOCOMPLETE_H_

#include <cstddef>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

// Chromium's omnibox for the app's command bar, in the shape of ArcCore's
// autocomplete result and match. No Chromium headers here.

namespace oa {

struct AutocompleteMatch {
  // Chromium's AutocompleteMatchTypeToString, such as "history-url".
  std::string type;
  // Chromium's AutocompleteProvider::TypeToString, such as "HistoryURL".
  std::string provider;
  std::string contents;
  std::string description;
  std::string destination_url;
  std::string fill_into_edit;
  std::string inline_autocompletion;
  std::string keyword;
  int relevance = 0;
  bool allowed_to_be_default = false;
  bool deletable = false;
  bool swap_contents_and_description = false;
  bool from_keyword = false;
  // Kept from the previous result while providers still answer.
  bool from_previous = false;
  // Chromium's additional info, such as "typed count" and "visit count".
  std::map<std::string, std::string> additional_info;
};

// The arguments of ArcCore's
// autocomplete:cursorPosition:preventInlineAutocomplete:startFresh:keyword:.
struct AutocompleteInput {
  std::string text;
  // In UTF-16 code units, as the app's text field counts.
  size_t cursor_position = 0;
  bool prevent_inline_autocomplete = false;
  // A new command bar session.
  bool start_fresh = false;
  // A search engine's keyword when searching only it.
  std::string keyword;
  // The page the input edits, when it edits one.
  std::string current_url;
};

// As ArcCore's ArcAutocompleteResult.
struct AutocompleteResult {
  // Chromium's combined result, in its order; it holds at most 8 matches.
  std::vector<AutocompleteMatch> combined_matches;
  // Every provider's own matches, provider by provider, which include the ones
  // the combined result's cap left out.
  std::vector<AutocompleteMatch> per_provider_matches;
};

class Autocomplete {
 public:
  // Posted, at least once and again as providers answer, until the next Start.
  using ResultCallback =
      std::function<void(const AutocompleteResult& result, bool done)>;

  virtual ~Autocomplete() = default;

  // Replaces a running query, as ArcCore's autocomplete:...completion: does.
  // Before the profile has loaded, the last start waits for it.
  virtual void Start(const AutocompleteInput& input,
                     ResultCallback callback) = 0;
  virtual void Stop() = 0;
  // Finds the match by type, contents and URL in the current result, as ADK's
  // deletable autocomplete matches do, and has its provider delete it. The
  // current start's callback gets the result without it.
  virtual void DeleteMatch(const AutocompleteMatch& match) = 0;
};

// Loads the app profile `profile_id` if needed and keeps a Chromium
// AutocompleteController for it until the result is destroyed. ArcCore keeps
// one per window.
std::unique_ptr<Autocomplete> CreateAutocomplete(const std::string& profile_id);

}  // namespace oa

#endif  // OA_PUBLIC_AUTOCOMPLETE_H_
