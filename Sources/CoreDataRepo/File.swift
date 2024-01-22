//
//  DataRepo.swift
//
//
//  Created by Sergey Tristan on 22.01.2024.
//


import Foundation
import CoreData
import Combine

@available(iOS 13.0, *)
public class DataRepo<Entity:NSManagedObject> {
    private var _context:NSManagedObjectContext
    @Published private var _predicate:NSPredicate = NSPredicate.init(value: false)
    private var _sort:[NSSortDescriptor] = []
    private var _limit:Int = 0
    private var _includePending = false
    private var _refresher:NSNotification.Name
    
    public init(_ context:NSManagedObjectContext,
         sort:[NSSortDescriptor] = [],
         limit:Int = 0,
         includePending:Bool = false,
         refresher: NSNotification.Name = NSManagedObjectContext.didChangeObjectsNotification
    ) {
        _context = context
        _sort = sort
        _limit = limit
        _includePending = includePending
        _refresher = refresher
    }
    
    public func publisher() -> any Publisher<[Entity], Never> {
        NotificationCenter.default
            .publisher(for: _refresher, object: nil)
            .map { _ in }
            .prepend(())
            .combineLatest($_predicate)
            .map { value in
                return self._context.fetch(Entity.self, for: value.1, sorting: self._sort, includePending: self._includePending, limit: self._limit)
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
   
    public func predicate(_ predicate: NSPredicate) {
        _predicate = predicate
        
    }
}


public extension NSManagedObjectContext {
    func fetch<T:NSManagedObject>(
        _ entityType:T.Type,
        for predicate:NSPredicate? = nil,
        sorting bySort:[NSSortDescriptor] = [],
        includePending:Bool = false,
        limit:Int? = nil
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
        } catch {
            return []
        }
    }
    
    func count<T:NSManagedObject>(
        _ entityType:T.Type,
        for predicate:NSPredicate? = nil,
        includePending:Bool = true
    ) -> Int {
        
        let entityName = String(describing: entityType)
        let entity = NSEntityDescription.entity(forEntityName: entityName, in: self)
        let request = NSFetchRequest<T>(entityName: entityName)
        request.entity = entity
        request.predicate = predicate
        request.includesPendingChanges = includePending
        do {
            return try count(for: request)
        } catch {
            return 0
        }
    }
}

