import DevKit
import Foundation

let engine = AppEngine.make()
exit(engine.run { ApplicationDelegate.start(engine: engine) })
