import AppKit
import Foundation

extension WindowModel {
    var littleDestinationSpace: SidebarSpace? { little?.destinationSpaceID.flatMap { state.space($0) } }

    /// As Arc's: worked out as the window is made and each time it becomes key, and not when its profile changes.
    func updateLittleDestination() {
        guard let profileID = little?.profile else { return }
        little?.destinationSpaceID = littleDestination(profileID)
    }

    func openInLittleDestination() {
        if let spaceID = little?.destinationSpaceID { moveLittlePage(toSpace: spaceID) }
    }

    /// Arc's `moveContentToStandardGlobalWindow`: the shown page goes, live, to the top of the Space in the standard
    /// window the app picks for it.
    func moveLittlePage(toSpace spaceID: UUID) {
        little?.showsMoveMenu = false
        guard isLittle, let tabID = selectedTabID else { return }
        moveItems([tabID], toSpace: spaceID)
    }

    /// As seen in Arc's chip: the profiles that have a Space.
    var littleProfiles: [ProfileState] {
        profiles.filter { profile in state.spaces.contains { $0.profileID == profile.id } }
    }

    /// As seen in Arc: the tip counts each showing, twice at most, and only its ✕ takes it away.
    func showLittleTipIfDue() {
        let count = UserDefaults.standard.integer(forKey: LittleBrowserPreferences.tipCountKey)
        guard let little, little.session.entryPoint.showsTip, !little.showsTip, count < 2 else { return }
        UserDefaults.standard.set(count + 1, forKey: LittleBrowserPreferences.tipCountKey)
        self.little?.showsTip = true
    }
}
