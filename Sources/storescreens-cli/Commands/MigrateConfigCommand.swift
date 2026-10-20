import ArgumentParser
import Foundation
import StorescreensCore

struct MigrateConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "migrate-config", abstract: "Back up a version 3 configuration and keep only capture settings.")
    @Option(name: .long, help: "Configuration to migrate in place; preserves an exact .v3-backup.")
    var config = "storescreens.yml"
    func run() throws {
        let backup = try ConfigMigration.migrate(path: config)
        print("Wrote capture settings to \(config). Original saved in \(backup).")
        print("Keep the backup private if it contains credentials. Port its reviewed copy and layouts to Koubou, and use ASC CLI for App Store Connect.")
    }
}
