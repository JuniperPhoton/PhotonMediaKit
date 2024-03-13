//
//  File.swift
//
//
//  Created by Photon Juniper on 2023/10/30.
//

import Foundation
import PhotonUtility
import SwiftUI

public class MediaFilterOptions: ObservableObject {
    @Published public var isSizeFilterOn = false
    @Published public var sizeFilterOperation: FilterOperation = .greaterThan
    @Published public var filteredSizeUnit: SizeUnit = .megaBytes
    @Published public var filteredSize: Double = 0.0
    
    @Published public var isDurationFilterOn = false
    @Published public var filteredDuration: Double = 0.0
    @Published public var durationFilterOperation: FilterOperation = .greaterThan
    @Published public var filteredDurationUnit: DurationUnit = .minutes
    
    @Published public var favoritedOptions: FavoritedFilterOptions = .all
    
    public init() {
        // empty
    }
    
    public var isFilterOn: Bool {
        (isSizeFilterOn && filteredSize > 0) || (isDurationFilterOn && filteredDuration > 0) || favoritedOptions != .all
    }
    
    public func isSizeMeet(_ sizeInBytes: Int64?) -> Bool {
        if !isSizeFilterOn || filteredSize <= 0 {
            return true
        }
        
        guard let sizeInBytes = sizeInBytes else { return false }
        
        let targetSizeInBytes: Int64 = Int64(filteredSize * filteredSizeUnit.bytes)
        switch sizeFilterOperation {
        case .lessThan:
            return sizeInBytes < targetSizeInBytes
        case .equals:
            return sizeInBytes == targetSizeInBytes
        case .greaterThan:
            return sizeInBytes > targetSizeInBytes
        }
    }
    
    public func isDurationMeet(_ durationInSecs: Double?) -> Bool {
        if !isDurationFilterOn || filteredDuration <= 0 {
            return true
        }
        
        guard let durationInSecs = durationInSecs else { return false }
        
        let targetDurationInSecs: Double = Double(filteredDuration * Double(filteredDurationUnit.seconds))
        switch sizeFilterOperation {
        case .lessThan:
            return durationInSecs < targetDurationInSecs
        case .equals:
            return durationInSecs == targetDurationInSecs
        case .greaterThan:
            return durationInSecs > targetDurationInSecs
        }
    }
}

public enum DurationUnit: String, CaseIterable, Hashable, Localizable, Identifiable {
    case seconds
    case minutes
    case hours
    
    public var id: String { self.rawValue }
    
    public var localizedStringKey: LocalizedStringKey {
        LocalizedStringKey(self.rawValue)
    }
    
    public var seconds: Int {
        switch self {
        case .seconds:
            1
        case .minutes:
            60
        case .hours:
            60 * 60
        }
    }
}

public enum SizeUnit: String, CaseIterable, Hashable, Localizable, Identifiable {
    case megaBytes
    case gigaBytes
    
    public var id: String { self.rawValue }
    
    public var localizedStringKey: LocalizedStringKey {
        LocalizedStringKey(self.rawValue)
    }
    
    public var bytes: Double {
        switch self {
        case .megaBytes:
            return 1000 * 1000
        case .gigaBytes:
            return 1000 * 1000 * 1000
        }
    }
}

public enum FilterOperation: String, CaseIterable, Hashable, Localizable, Identifiable {
    case lessThan
    case equals
    case greaterThan
    
    public var id: String { self.rawValue }
    
    public var localizedStringKey: LocalizedStringKey {
        LocalizedStringKey(self.rawValue)
    }
}

public enum FavoritedFilterOptions: String, CaseIterable, Hashable, Localizable, Identifiable {
    case all = "FavoritedFilterOptionsAll"
    case favorited = "FavoritedFilterOptionsFavorited"
    case nonFavorited = "FavoritedFilterOptionsNonFavorited"
    
    public var id: String { self.rawValue }
    
    public var localizedStringKey: LocalizedStringKey {
        LocalizedStringKey(self.rawValue)
    }
}
