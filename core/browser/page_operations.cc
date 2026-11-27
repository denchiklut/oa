#include "oa/browser/page_impl.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/scoped_observation.h"
#include "base/timer/timer.h"
#include "content/public/browser/child_process_termination_info.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/render_process_host_observer.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "oa/common/page_operations.mojom.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"

namespace oa {
namespace {

using Frame = content::RenderFrameHost;

bool BelongsToPage(Frame* frame, content::WebContents* page) {
  return frame && page && frame->IsActive() &&
         frame->GetMainFrame() == page->GetPrimaryMainFrame();
}

// One request owns its endpoint until a reply, process exit or deadline.
class StyleSheetRequest : public content::RenderProcessHostObserver {
 public:
  StyleSheetRequest(base::WeakPtr<PageImpl> page,
                    Frame* frame,
                    const base::UnguessableToken& document,
                    const std::string& css,
                    Page::StyleSheetCallback callback)
      : page_(std::move(page)),
        document_(frame->GetWeakDocumentPtr()),
        callback_(std::move(callback)) {
    process_.Observe(frame->GetProcess());
    frame->GetRemoteAssociatedInterfaces()->GetInterface(&remote_);
    timer_.Start(FROM_HERE, base::Seconds(5), this,
                 &StyleSheetRequest::OnDeadline);
    remote_->InsertStyleSheet(
        document, css,
        base::BindOnce(&StyleSheetRequest::OnReply, base::Unretained(this)));
  }

 private:
  bool HasDocument() const {
    return page_ && BelongsToPage(document_.AsRenderFrameHostIfValid(),
                                  page_->web_contents());
  }

  void OnReply(bool inserted) {
    Finish(inserted && HasDocument() ? StyleSheetResult::kInserted
                                     : StyleSheetResult::kFrameGone);
  }

  void OnDeadline() {
    if (!HasDocument()) {
      Finish(StyleSheetResult::kFrameGone);
      return;
    }
    // A crash can close the pipe before Chromium reports the process exit.
    Finish(remote_.is_connected() ? StyleSheetResult::kTimedOut
                                  : StyleSheetResult::kDisconnected);
  }

  void RenderProcessExited(
      content::RenderProcessHost* host,
      const content::ChildProcessTerminationInfo& info) override {
    Finish(info.status == base::TERMINATION_STATUS_NORMAL_TERMINATION
               ? StyleSheetResult::kFrameGone
               : StyleSheetResult::kRendererCrashed);
  }

  void RenderProcessHostDestroyed(content::RenderProcessHost* host) override {
    Finish(StyleSheetResult::kFrameGone);
  }

  void Finish(StyleSheetResult result) {
    auto callback = std::move(callback_);
    delete this;
    callback(result);
  }

  base::WeakPtr<PageImpl> page_;
  content::WeakDocumentPtr document_;
  Page::StyleSheetCallback callback_;
  base::ScopedObservation<content::RenderProcessHost,
                          content::RenderProcessHostObserver>
      process_{this};
  mojo::AssociatedRemote<mojom::PageOperations> remote_;
  base::OneShotTimer timer_;
};

}  // namespace

std::vector<std::string> PageImpl::FrameIDs() const {
  std::vector<std::string> ids;
  if (auto* page = web_contents()) {
    page->GetPrimaryMainFrame()->ForEachRenderFrameHost([&](Frame* frame) {
      if (BelongsToPage(frame, page) && frame->IsRenderFrameLive()) {
        if (auto token = frame->GetEmbeddingToken()) {
          ids.push_back(token->ToString());
        }
      }
    });
  }
  return ids;
}

void PageImpl::InsertStyleSheet(const std::string& frame_id,
                                const std::string& css,
                                StyleSheetCallback callback) {
  auto* page = web_contents();
  auto token = base::UnguessableToken::DeserializeFromString(frame_id);
  Frame* target = nullptr;
  if (page && token) {
    page->GetPrimaryMainFrame()->ForEachRenderFrameHostWithAction(
        [&](Frame* frame) {
          if (BelongsToPage(frame, page) && frame->IsRenderFrameLive() &&
              frame->GetEmbeddingToken() == token) {
            target = frame;
            return Frame::FrameIterationAction::kStop;
          }
          return Frame::FrameIterationAction::kContinue;
        });
  }
  if (!target) {
    callback(StyleSheetResult::kFrameGone);
    return;
  }
  new StyleSheetRequest(weak_factory_.GetWeakPtr(), target, *token, css,
                        std::move(callback));
}

}  // namespace oa
