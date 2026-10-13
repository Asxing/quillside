//
//  AppState.swift
//  Quillside
//
//  Created on 2026-01-28.
//

import Foundation
import Combine

enum NotesDatabaseAccessTransition: Equatable {
    case unchanged
    case becameAvailable
    case becameUnavailable

    init(
        from previous: NotesDatabaseAccessStatus,
        to current: NotesDatabaseAccessStatus
    ) {
        if previous == current {
            self = .unchanged
        } else if current == .available {
            self = .becameAvailable
        } else {
            self = .becameUnavailable
        }
    }
}

/// 应用全局状态
///
/// 使用 ObservableObject 在 SwiftUI 视图间共享状态。
/// 所有属性都在主线程更新。
final class AppState: ObservableObject {
    
    // MARK: - Permission State
    
    /// 是否已获得 Accessibility 权限
    @Published var hasAccessibilityPermission: Bool = false

    /// Apple Notes 数据库是否可供只读 Backlinks 查询
    @Published var notesDatabaseAccess: NotesDatabaseAccessStatus = .checking

    /// Apple Notes Automation 权限；首次主动执行需要原生标识符的操作时才请求。
    @Published var automationAccess: AppleNotesAutomationStatus = .checking
    
    // MARK: - Notes App State
    
    /// Apple Notes 是否正在运行
    @Published var isNotesRunning: Bool = false
    
    /// Apple Notes 是否是前台应用
    @Published var isNotesFrontmost: Bool = false
    
    @Published var showOnboarding: Bool = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    
    // MARK: - Computed Properties
    
    /// 应用是否完全可用 (有权限且 Notes 运行中)
    var isFullyOperational: Bool {
        hasAccessibilityPermission && isNotesRunning
    }

    var canUseBacklinks: Bool {
        notesDatabaseAccess == .available
    }
    
    /// 状态描述文本
    var statusDescription: String {
        if !hasAccessibilityPermission {
            return "需要辅助功能权限"
        }
        if notesDatabaseAccess == .permissionRequired {
            return "笔记链接与 Backlinks 需要完全磁盘访问"
        }
        if case .unavailable = notesDatabaseAccess {
            return "Backlinks 数据库不可用"
        }
        if !isNotesRunning {
            return "Apple Notes 未运行"
        }
        if isNotesFrontmost {
            return "已激活"
        }
        return "待命中"
    }
}
