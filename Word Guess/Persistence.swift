//
//  Persistence.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import CoreData

class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for _ in 0..<10 {
            let newItem = EasyItem(context: viewContext)
            newItem.timestamp = Date()
        }
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Word_Guess")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    func set(item: EasyItem?, current: Int, guesses: Guesses) {
        delete(item: item)
        let item = EasyItem(context: container.viewContext)
        item.timestamp = Date()
        item.current = Int32(current)
        item.guesses = guesses
        save()
    }
    
    func set(item: RegularItem?, current: Int, guesses: Guesses) {
        delete(item: item)
        let item = RegularItem(context: container.viewContext)
        item.timestamp = Date()
        item.current = Int32(current)
        item.guesses = guesses
        save()
    }
    
    func set(item: HardItem?, current: Int, guesses: Guesses) {
        delete(item: item)
        let item = HardItem(context: container.viewContext)
        item.timestamp = Date()
        item.current = Int32(current)
        item.guesses = guesses
        save()
    }
    
    func delete(item: NSManagedObject?) {
        guard let item else { return }
        container.viewContext.delete(item)
        save()
    }
    
    func save() {
        do {
            if container.viewContext.hasChanges {
                try container.viewContext.save()
            }
        } catch {
            print(error)
        }
    }
}
