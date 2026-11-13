// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_BROWSER_UI_VIDEO_OVERLAY_WINDOW_IMPL_H_
#define OA_BROWSER_UI_VIDEO_OVERLAY_WINDOW_IMPL_H_

#include <memory>

#include "base/memory/weak_ptr.h"
#include "components/viz/common/surfaces/surface_id.h"
#include "content/public/browser/overlay_window.h"
#include "oa/public/page.h"
#include "ui/accelerated_widget_mac/accelerated_widget_mac.h"

@class OAVideoOverlayView;

namespace content {
class VideoPictureInPictureWindowController;
}

namespace ui {
class DisplayCALayerTree;
class LayerSurface;
class RecyclableCompositorMac;
}  // namespace ui

namespace oa {

class PageImpl;

// The window Chromium shows a page's picture-in-picture video in, as
// ArcCore's coordinator: no window of its own. It draws the video's surface
// into a view the app hosts in its window, and turns show, hide and close into
// events on the page. Owned by Chromium's controller for the page.
class VideoOverlayWindowImpl : public content::VideoOverlayWindow,
                               public ui::AcceleratedWidgetMacNSView {
 public:
  explicit VideoOverlayWindowImpl(
      content::VideoPictureInPictureWindowController* controller);
  VideoOverlayWindowImpl(const VideoOverlayWindowImpl&) = delete;
  VideoOverlayWindowImpl& operator=(const VideoOverlayWindowImpl&) = delete;
  ~VideoOverlayWindowImpl() override;

  // The view's size changed: the surface follows it, as ArcCore's view does.
  void Render();

  // content::VideoOverlayWindow:
  bool IsActive() const override;
  void Close() override;
  void ShowInactive() override;
  void Hide() override;
  bool IsVisible() const override;
  gfx::Rect GetBounds() override;
  void UpdateNaturalSize(const gfx::Size& natural_size) override;
  void SetPlaybackState(PlaybackState playback_state) override {}
  void SetPlayPauseButtonVisibility(bool is_visible) override {}
  void SetSkipAdButtonVisibility(bool is_visible) override {}
  void SetNextTrackButtonVisibility(bool is_visible) override {}
  void SetPreviousTrackButtonVisibility(bool is_visible) override {}
  void SetHidePictureInPictureButtonVisibility(bool is_visible) override {}
  void SetMicrophoneMuted(bool muted) override {}
  void SetCameraState(bool turned_on) override {}
  void SetMediaMuted(bool muted) override {}
  void SetToggleMicrophoneButtonVisibility(bool is_visible) override {}
  void SetToggleCameraButtonVisibility(bool is_visible) override {}
  void SetHangUpButtonVisibility(bool is_visible) override {}
  void SetNextSlideButtonVisibility(bool is_visible) override {}
  void SetPreviousSlideButtonVisibility(bool is_visible) override {}
  void SetMediaPosition(const media_session::MediaPosition& position) override {
  }
  void SetSourceTitle(const std::u16string& source_title) override {}
  void SetFaviconImages(
      const std::vector<media_session::MediaImage>& images) override {}
  void SetSurfaceId(const viz::SurfaceId& surface_id) override;
  void SetPlaybackControlsVisibility(bool is_visible) override {}
  void SetImmersiveVideoOptions(
      const content::ImmersiveOptions& options) override {}

  // ui::AcceleratedWidgetMacNSView:
  void AcceleratedWidgetCALayerParamsUpdated(
      gfx::CALayerParams ca_layer_params) override;

 private:
  void StopRendering();
  void Notify(PictureInPictureEvent::Kind kind);

  // Not the controller: it can be mid-destruction when this is destroyed.
  base::WeakPtr<PageImpl> page_;
  std::unique_ptr<ui::RecyclableCompositorMac> compositor_;
  std::unique_ptr<ui::LayerSurface> surface_layer_;
  std::unique_ptr<ui::DisplayCALayerTree> display_ca_layer_tree_;
  viz::SurfaceId surface_id_;
  OAVideoOverlayView* __strong view_;
};

}  // namespace oa

#endif  // OA_BROWSER_UI_VIDEO_OVERLAY_WINDOW_IMPL_H_
