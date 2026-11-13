// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "oa/browser/ui/video_overlay_window_impl.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#include <utility>

#include "base/memory/raw_ptr.h"
#include "cc/layers/deadline_policy.h"
#include "content/public/browser/context_factory.h"
#include "content/public/browser/video_picture_in_picture_window_controller.h"
#include "content/public/browser/web_contents.h"
#include "oa/browser/page_impl.h"
#include "ui/accelerated_widget_mac/display_ca_layer_tree.h"
#include "ui/compositor/compositor.h"
#include "ui/compositor/layer_surface.h"
#include "ui/compositor/recyclable_compositor_mac.h"
#include "ui/display/types/display_constants.h"
#include "ui/gfx/display_color_spaces.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/mac/coordinate_conversion.h"

@interface OAVideoOverlayView : NSView
- (instancetype)initWithFrame:(NSRect)frame
                        layer:(CALayer*)layer
                        owner:(oa::VideoOverlayWindowImpl*)owner;
- (void)clearOwner;
@end

@implementation OAVideoOverlayView {
  raw_ptr<oa::VideoOverlayWindowImpl> _owner;
}

- (instancetype)initWithFrame:(NSRect)frame
                        layer:(CALayer*)layer
                        owner:(oa::VideoOverlayWindowImpl*)owner {
  if ((self = [super initWithFrame:frame])) {
    _owner = owner;
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.layer = layer;
    self.wantsLayer = YES;
  }
  return self;
}

- (void)clearOwner {
  _owner = nullptr;
}

- (void)setFrameSize:(NSSize)size {
  [super setFrameSize:size];
  if (_owner) {
    _owner->Render();
  }
}

@end

namespace oa {

VideoOverlayWindowImpl::VideoOverlayWindowImpl(
    content::VideoPictureInPictureWindowController* controller) {
  if (PageImpl* page = PageImpl::FromWebContents(
          controller->GetWebContents()->GetOutermostWebContents())) {
    page_ = page->GetWeakPtr();
  }
  const gfx::Rect& source = controller->GetSourceBounds();
  // The tree's own sublayer only follows changes of the layer's size, so it is
  // built while the layer has none.
  CALayer* layer = [CALayer layer];
  display_ca_layer_tree_ = std::make_unique<ui::DisplayCALayerTree>(layer);
  view_ = [[OAVideoOverlayView alloc]
      initWithFrame:NSMakeRect(0, 0, source.width(), source.height())
              layer:layer
              owner:this];
  compositor_ = std::make_unique<ui::RecyclableCompositorMac>(
      content::GetContextFactory());
  compositor_->widget()->SetNSView(this);
  surface_layer_ = std::make_unique<ui::LayerSurface>();
  compositor_->compositor()->SetRootLayer(surface_layer_.get());
  if (page_) {
    page_->NotifyPictureInPicture(
        {.kind = PictureInPictureEvent::Kind::kCreated,
         .x = static_cast<double>(source.x()),
         .y = static_cast<double>(source.y()),
         .width = static_cast<double>(source.width()),
         .height = static_cast<double>(source.height())},
        (__bridge void*)view_);
  }
}

VideoOverlayWindowImpl::~VideoOverlayWindowImpl() {
  StopRendering();
  [view_ clearOwner];
  compositor_->widget()->ResetNSView();
  compositor_->compositor()->SetRootLayer(nullptr);
  Notify(PictureInPictureEvent::Kind::kDestroyed);
}

void VideoOverlayWindowImpl::Render() {
  gfx::Size size(view_.bounds.size.width, view_.bounds.size.height);
  if (!surface_id_.is_valid() || size.IsEmpty()) {
    return;
  }
  surface_layer_->SetBounds(gfx::Rect(size));
  surface_layer_->SetShowSurface(surface_id_, size,
                                 cc::DeadlinePolicy::UseDefaultDeadline(),
                                 /*stretch_content_to_fill_bounds=*/true);
  // As ArcCore: the view's size in points is the compositor's size in pixels.
  compositor_->UpdateSurface(size, 1.0f, gfx::DisplayColorSpaces(),
                             display::kInvalidDisplayId, 60.0f);
  compositor_->Unsuspend();
}

void VideoOverlayWindowImpl::StopRendering() {
  if (!surface_id_.is_valid()) {
    return;
  }
  compositor_->compositor()->RemoveChildFrameSink(surface_id_.frame_sink_id());
  // A later resize of the view must not draw the session that ended.
  surface_id_ = viz::SurfaceId();
  compositor_->Suspend();
}

void VideoOverlayWindowImpl::Notify(PictureInPictureEvent::Kind kind) {
  if (page_) {
    page_->NotifyPictureInPicture({.kind = kind});
  }
}

bool VideoOverlayWindowImpl::IsActive() const {
  return view_.window.isKeyWindow;
}

void VideoOverlayWindowImpl::Close() {
  StopRendering();
  Notify(PictureInPictureEvent::Kind::kClose);
}

void VideoOverlayWindowImpl::ShowInactive() {
  Notify(PictureInPictureEvent::Kind::kShow);
}

void VideoOverlayWindowImpl::Hide() {
  StopRendering();
  Notify(PictureInPictureEvent::Kind::kHide);
}

bool VideoOverlayWindowImpl::IsVisible() const {
  return view_.window.visible && !view_.hiddenOrHasHiddenAncestor;
}

gfx::Rect VideoOverlayWindowImpl::GetBounds() {
  NSWindow* window = view_.window;
  return window ? gfx::ScreenRectFromNSRect(window.frame) : gfx::Rect();
}

void VideoOverlayWindowImpl::UpdateNaturalSize(const gfx::Size& natural_size) {
  if (page_) {
    page_->NotifyPictureInPicture(
        {.kind = PictureInPictureEvent::Kind::kResolutionChanged,
         .width = static_cast<double>(natural_size.width()),
         .height = static_cast<double>(natural_size.height())});
  }
}

void VideoOverlayWindowImpl::SetSurfaceId(const viz::SurfaceId& surface_id) {
  if (surface_id != surface_id_) {
    StopRendering();
    surface_id_ = surface_id;
    if (surface_id_.is_valid()) {
      compositor_->compositor()->AddChildFrameSink(surface_id_.frame_sink_id());
    }
  }
  Render();
}

void VideoOverlayWindowImpl::AcceleratedWidgetCALayerParamsUpdated(
    gfx::CALayerParams ca_layer_params) {
  display_ca_layer_tree_->UpdateCALayerTree(std::move(ca_layer_params));
}

}  // namespace oa
