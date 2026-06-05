//
//  DataRepo.swift
//
//  Created by Sergey Tristan on 22.01.2026.
//

import Foundation
import CoreData
import Combine

public final class DataRepo<Entity:NSManagedObject> {
    private let predicate = CurrentValueSubject<NSPredicate, Never>(.falsePredicate)
    
    private var context:NSManagedObjectContext
    private var sort:[NSSortDescriptor] = []
    private var limit:Int? = nil
    private var includePending = false
    private var refresher:Notification.Name
    private var debug:Bool
    
    public init(_ context:NSManagedObjectContext,
                for predicate: NSPredicate = .falsePredicate,
                sort:[NSSortDescriptor] = [],
                limit:Int? = nil,
                includePending:Bool = false,
                refresher: NSNotification.Name = .managedContextChanged,
                debug: Bool = false
    ) {
        self.context = context
        self.predicate.send(predicate)
        self.sort = sort
        self.limit = limit
        self.includePending = includePending
        self.refresher = refresher
        self.debug = debug
    }
    
    public lazy var items: AnyPublisher<[Entity], Never> = { self.publisher() }()
    
    private func publisher() -> AnyPublisher<[Entity], Never> {
        return NotificationCenter.default
            .publisher(for: refresher)
            .prepend(Notification(name: refresher))
            .combineLatest(predicate)
            .throttle(for: .seconds(0.3), scheduler: DispatchQueue.global(), latest: true)
            .map { [weak self] (_, predicate) in
                let subject = PassthroughSubject<[Entity], Never>()
                
                let task = Task { [weak self] in
                    guard let self else {
                        subject.send([])
                        subject.send(completion: .finished)
                        return
                    }
                    let result = await self.context.fetchAsync(Entity.self,
                                                               predicate: predicate,
                                                               sortDescriptors: self.sort,
                                                               includePending: self.includePending,
                                                               limit: self.limit,
                                                               debug: self.debug)
                    guard !Task.isCancelled else { return }
                    subject.send(result)
                    subject.send(completion: .finished)
                }
                
                return subject
                    .handleEvents(receiveCancel: { task.cancel() })
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    public func fetch(for predicate:NSPredicate) {
        self.predicate.send(predicate)
    }
}
