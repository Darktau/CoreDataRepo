//
//  DataCounter.swift
//
//  Created by Sergey Tristan on 06.03.2024.
//

import Foundation
import CoreData
import Combine

public final class DataCounter<Entity:NSManagedObject> {
    
    private let predicates = CurrentValueSubject<[String:NSPredicate], Never>(["Empty": .falsePredicate])
    private var context:NSManagedObjectContext
    private var refresher:NSNotification.Name
    private var debug:Bool
    
    public init(_ context:NSManagedObjectContext,
                for predicates:[String:NSPredicate] = ["Empty": .falsePredicate],
                refresher: NSNotification.Name = .managedContextChanged,
                debug:Bool = false
    ) {
        self.context = context
        self.refresher = refresher
        self.predicates.send(predicates)
        self.debug = debug
    }
    
    public lazy var items: AnyPublisher<[String:Int], Never> = { self.publisher() }()
    
    private func publisher() -> AnyPublisher<[String:Int], Never> {
        NotificationCenter.default
            .publisher(for: refresher)
            .prepend(Notification(name: refresher))
            .combineLatest(predicates)
            .map {[weak self] (_, predicates) in
                guard let self else { return [:]}
                var result:[String:Int] = [:]
                self.context.performAndWait {
                    predicates.forEach { predicate in
                        result[predicate.key] = self.context.count(Entity.self, for: predicate.value, debug: self.debug)
                    }
                }
                return result
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    public func count(for predicates:[String:NSPredicate]) {
        self.predicates.send(predicates)
    }
}

