//
//  ManagedContext.swift
//
//
//  Created by Sergey Tristan on 22.01.2026.
//

import Foundation
import CoreData

public extension NSManagedObjectContext {
    public func fetch<T:NSManagedObject>(
        _ entityType:T.Type,
        for predicate:NSPredicate? = nil,
        sorting bySort:[NSSortDescriptor] = [],
        includePending:Bool = false,
        limit:Int? = nil,
        debug:Bool = false
    ) -> [T] {
        
        let entityName = String(describing: entityType)
        let entity = NSEntityDescription.entity(forEntityName: entityName, in: self)
        let request = NSFetchRequest<T>(entityName: entityName)
        request.entity = entity
        request.predicate = predicate
        request.sortDescriptors = bySort
        if limit != nil {
            request.fetchLimit = limit!
        }
        request.includesPendingChanges = includePending
        do {
            return try fetch(request)
        } catch let error {
            if debug {
                let entity = T.entity().name ?? String(describing: T.self)
                print("[fetch] Fetch failed for '\(entity)': \(error)")
            }
            return []
        }
    }
    
    public func count<T:NSManagedObject>(
        _ entityType:T.Type,
        for predicate:NSPredicate? = nil,
        includePending:Bool = true,
        debug:Bool = false
    ) -> Int {
        
        let entityName = String(describing: entityType)
        let entity = NSEntityDescription.entity(forEntityName: entityName, in: self)
        let request = NSFetchRequest<T>(entityName: entityName)
        request.entity = entity
        request.predicate = predicate
        request.includesPendingChanges = includePending
        do {
            return try count(for: request)
        } catch let error {
            if debug {
                let entity = T.entity().name ?? String(describing: T.self)
                print("[count] Fetch failed for '\(entity)': \(error)")
            }
            return 0
        }
    }
}

public extension NSManagedObjectContext {
    
    /// Асинхронный fetch для любого контекста (потокобезопасно)
    public func fetchAsync<T: NSManagedObject>(
        _ entityType: T.Type,
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor] = [],
        includePending: Bool = false,
        limit: Int? = nil,
        debug:Bool = false
    ) async -> [T] {
        guard !Task.isCancelled else { return [] }
        let sendablePredicate = SendablePredicate(value: predicate)
        let sendableSort = SendableSort(value: sortDescriptors)
        return await perform {
            guard !Task.isCancelled else { return [] }
            
            let request = entityType.fetchRequest()
            request.predicate = sendablePredicate.value
            request.sortDescriptors = sendableSort.value
            request.includesPendingChanges = includePending
            if let limit = limit { request.fetchLimit = limit }
            do {
                return try self.fetch(request) as [T]
            } catch let error {
                if debug {
                    let entity = T.entity().name ?? String(describing: T.self)
                    print("[fetchAsync] Fetch failed for '\(entity)': \(error)")
                }
                return []
            }
        }
    }
    
    public func countAsync<T: NSManagedObject>(
        _ entityType: T.Type,
        predicate: NSPredicate? = nil,
        includePending: Bool = true,
        debug:Bool = false
    ) async -> Int {
        let sendablePredicate = SendablePredicate(value: predicate)
        return await perform {
            let request = entityType.fetchRequest()
            request.predicate = sendablePredicate.value
            request.includesPendingChanges = includePending
            do {
                return try self.count(for:request)
            } catch let error {
                if debug {
                    let entity = T.entity().name ?? String(describing: T.self)
                    print("[countAsync] Fetch failed for '\(entity)': \(error)")
                }
                return 0
            }
        }
    }
}


struct SendablePredicate: @unchecked Sendable {
    let value: NSPredicate?
}
struct SendableSort: @unchecked Sendable {
    let value: [NSSortDescriptor]
}



public extension NSManagedObjectContext {
    
    public func saveChanges(
        _ refresher: Notification.Name = .managedContextChanged,
        push:Bool = true) async -> Bool
    {
        do {
            if hasChanges {
                try save()
                
                if push {
                    await MainActor.run {
                        NotificationCenter.default.post(name: refresher, object: nil)
                    }
                }
            }
            return true
        } catch {
            return false
        }
    }
    
    
    public func saveChangesSync(
        _ refresher: Notification.Name = .managedContextChanged,
        push:Bool = true) -> Bool
    {
        do {
            if hasChanges {
                try save()
                
                if push {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: refresher, object: nil)
                    }
                }
            }
            return true
        } catch {
            return false
        }
    }
}

