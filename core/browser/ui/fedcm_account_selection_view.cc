// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "chrome/browser/ui/webid/account_selection_view.h"

namespace {

// As in Arc, keep Chromium's FedCM controller and dismiss at the point where
// it would present its UI. The dismissal callback can destroy this view.
class FedCmAccountSelectionView final : public AccountSelectionView {
 public:
  using AccountSelectionView::AccountSelectionView;

  bool Show(const content::RelyingPartyData&,
            const std::vector<IdentityProviderDataPtr>&,
            const std::vector<IdentityRequestAccountPtr>&,
            blink::mojom::RpMode,
            const std::vector<IdentityRequestAccountPtr>&) override {
    return Dismiss();
  }

  bool ShowFailureDialog(const content::RelyingPartyData&,
                         const std::string&,
                         blink::mojom::RpContext,
                         blink::mojom::RpMode,
                         const content::IdentityProviderMetadata&) override {
    return Dismiss();
  }

  bool ShowErrorDialog(const content::RelyingPartyData&,
                       const std::string&,
                       blink::mojom::RpContext,
                       blink::mojom::RpMode,
                       const content::IdentityProviderMetadata&,
                       const std::optional<TokenError>&) override {
    return Dismiss();
  }

  bool ShowLoadingDialog(const content::RelyingPartyData&,
                         const std::string&,
                         blink::mojom::RpContext,
                         blink::mojom::RpMode) override {
    return Dismiss();
  }

  bool ShowVerifyingDialog(const content::RelyingPartyData&,
                           const IdentityProviderDataPtr&,
                           const IdentityRequestAccountPtr&,
                           Account::SignInMode,
                           blink::mojom::RpMode) override {
    return Dismiss();
  }

  bool ShowNativeAppUi(const content::NativeAppRequestOptions&) override {
    return false;
  }

  void OnPageActionClicked() override {}
  std::string GetTitle() const override { return {}; }
  std::optional<std::string> GetSubtitle() const override {
    return std::nullopt;
  }
  void ShowUrl(LinkType, const GURL&) override {}
  content::WebContents* ShowModalDialog(
      const GURL&,
      blink::mojom::RpMode,
      content::IdentityRequestDialogController::ShownModalAsyncCallback)
      override {
    return nullptr;
  }
  void CloseModalDialog() override {}
  content::WebContents* GetRpWebContents() override { return nullptr; }

 private:
  bool Dismiss() {
    delegate_->OnDismiss(
        content::IdentityRequestDialogController::DismissReason::kOther);
    return false;
  }
};

}  // namespace

std::unique_ptr<AccountSelectionView> AccountSelectionView::Create(
    Delegate* delegate) {
  return std::make_unique<FedCmAccountSelectionView>(delegate);
}
