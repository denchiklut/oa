#ifndef OA_RENDERER_CONTENT_RENDERER_CLIENT_H_
#define OA_RENDERER_CONTENT_RENDERER_CLIENT_H_
#include <memory>
namespace content {
class ContentRendererClient;
}
namespace oa {
std::unique_ptr<content::ContentRendererClient> CreateRendererClient();
}  // namespace oa
#endif
