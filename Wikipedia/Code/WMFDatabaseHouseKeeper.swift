import Foundation

@objc class WMFDatabaseHouseKeeper2 : NSObject {
    
    @objc func performHouseKeepingOnManagedObjectContext(_ moc: NSManagedObjectContext)  throws {
        
        try deleteStaleUnreferencedArticles(moc)
    }
    
    private func deleteStaleUnreferencedArticles(_ moc: NSManagedObjectContext) throws {
        
        /**
 
        Find `WMFContentGroup`s more than 30 days old.
 
        */
        
        let midnightTodayUTC = (Date() as NSDate).wmf_midnightUTCDateFromLocal!
        let utcCalendar = NSCalendar.wmf_utcGregorian() as Calendar
        let thirtyDaysAgoMidnightUTC = utcCalendar.date(byAdding: .day, value: -30, to: midnightTodayUTC, wrappingComponents: true)
        
        let allContentGroupFetchRequest = WMFContentGroup.fetchRequest()
        allContentGroupFetchRequest.propertiesToFetch = ["key", "midnightUTCDate", "content", "articleURLString"]
        
        let allContentGroups = try moc.fetch(allContentGroupFetchRequest)
        var referencedArticleKeys = Set<String>(minimumCapacity: allContentGroups.count * 5 + 1)
        
        for group in allContentGroups {
            if group.midnightUTCDate?.compare(thirtyDaysAgoMidnightUTC!) == .orderedAscending {
                moc.delete(group)
                continue
            }
            
            if let articleURLDatabaseKey = (group.articleURL as NSURL?)?.wmf_articleDatabaseKey {
                referencedArticleKeys.insert(articleURLDatabaseKey)
            }
            
            guard let content = group.content as Array! else {
                assertionFailure("Unknown Content Type")
                continue
            }
            
            for obj in content {
                
                switch (group.contentType, obj) {
                    
                case (.URL, let url as NSURL):
                    guard let key = url.wmf_articleDatabaseKey else {
                        continue
                    }
                    referencedArticleKeys.insert(key)
                    
                case (.topReadPreview, let preview as WMFFeedTopReadArticlePreview):
                    guard let key = (preview.articleURL as NSURL).wmf_articleDatabaseKey else {
                        continue
                    }
                    referencedArticleKeys.insert(key)
                    
                case (.story, let story as WMFFeedNewsStory):
                    if let articlePreviews = story.articlePreviews {
                        for preview in articlePreviews {
                            guard let key = (preview.articleURL as NSURL).wmf_articleDatabaseKey else {
                                continue
                            }
                            referencedArticleKeys.insert(key)
                        }
                    }
                    
                case (.URL, _),
                     (.topReadPreview, _),
                     (.story, _),
                     (.image, _),
                     (.announcement, _):
                    break
                    
                default:
                    assertionFailure("Unknown Content Type")
                }
            }
        }
        
      
        /** 
  
        Find WMFArticles that are cached previews only, and have no user-defined state.
 
            - A `viewedDate` of null indicates that the article was never viewed
            - A `savedDate` of null indicates that the article is not saved
            - A `placesSortOrder` of null indicates it is not currently visible on the Places map
            - Items with `isExcludedFromFeed == YES` need to stay in the database so that they will continue to be excluded from the feed
        */
        
        let articlesToDeleteFetchRequest = WMFArticle.fetchRequest()
        var articlesToDeletePredicate = NSPredicate(format: "viewedDate == NULL && savedDate == NULL && placesSortOrder == NULL && isExcludedFromFeed == %@", NSNumber(booleanLiteral: false))
        if referencedArticleKeys.count > 0 {
            let referencedKeysPredicate = NSPredicate(format: "!(key IN %@)", referencedArticleKeys)
            articlesToDeletePredicate = NSCompoundPredicate(andPredicateWithSubpredicates:[articlesToDeletePredicate,referencedKeysPredicate])
        }
        
        articlesToDeleteFetchRequest.predicate = articlesToDeletePredicate
        articlesToDeleteFetchRequest.propertiesToFetch = ["key", "viewedDate", "savedDate", "isExcludedFromFeed"]
        
        let articlesToDelete = try moc.fetch(articlesToDeleteFetchRequest)
        
        for obj in articlesToDelete {
            moc.delete(obj)
        }
        
        if (moc.hasChanges) {
            try moc.save()
        }
    }
}
