#ifndef OA_PUBLIC_PROFILES_H_
#define OA_PUBLIC_PROFILES_H_

#include <functional>
#include <string>
#include <vector>

namespace oa {

// The app's profiles as Chromium keeps them, in the shape of ArcCore's browser
// context calls. Chromium owns the names; the app stores none.
struct ProfileAttributes {
  std::string id;
  std::string name;
};

// As ADK's BrowserContextType: a profile's own context, or its incognito one,
// which is the profile's primary off-the-record profile.
enum class BrowserContextType { kNormal, kIncognito };

// Every app profile Chromium has attributes for, loaded or not, in its
// storage's order, as ArcCore's availableBrowserContextAttributes.
std::vector<ProfileAttributes> GetAvailableProfileAttributes();

// Creates and loads a profile named `name`, as Chrome's
// CreateMultiProfileAsync does but in a directory of the app's naming.
// `completion` gets its identifier, or an empty string if it can't.
void CreateProfile(
    const std::string& name,
    std::function<void(const std::string& profile_id)> completion);

// Sets Chrome's local profile name, loading the profile first if Chromium has
// no attributes for it yet.
void SetProfileName(const std::string& profile_id, const std::string& name);

// Forgets the profile and deletes its directory once Chrome has unloaded it,
// which is at once when the app holds none of its pages. True if the deletion
// is scheduled, false for a profile Chromium doesn't know.
bool DeleteProfile(const std::string& profile_id);

}  // namespace oa

#endif  // OA_PUBLIC_PROFILES_H_
