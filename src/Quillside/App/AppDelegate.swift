//
//  AppDelegate.swift
//  Quillside
//
//  Created on 2026-01-28.
//

import AppKit
import Combine
import os.log
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    
    private let logger = Logger(subsystem: "com.opennotes.app", category: "AppDelegate")
    
    let appState = AppState()
    
    private let accessibilityBridge = AccessibilityBridge.shared
    
    private var windowTracker: WindowTrackService?
    private var floatingBarController: FloatingBarWindowController?
    private var keyboardMonitor: KeyboardMonitorService?
    private var editorInputObserver: EditorInputObserver?
    private var markdownTrigger: MarkdownTriggerService?
    private var slashCommandService: SlashCommandService?
    private var slashMenuController: SlashMenuWindowController?
    private var backlinksPanelController: BacklinksPanelWindowController?
    private var noteActionsBarController: NoteActionsBarWindowController?
    private var statusBarController: StatusBarController?
    private var onboardingWindow: NSWindow?
    
    private var cancellables = Set<AnyCancellable>()
    private var serviceCancellables = Set<AnyCancellable>()
    private var isRefreshingDatabaseAccess = false
    private var isRefreshingAutomationAccess = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Quillside 启动中...")
        SettingsWindowController.shared.bind(appState: appState)
        statusBarController = StatusBarController(appState: appState)
        refreshNotesProcessStatus()
        
        checkAccessibilityPermission()
        refreshDatabaseAccessStatus()
        refreshAutomationAccessStatus()
        
        if accessibilityBridge.isTrusted {
            initializeServices()
        }

        setupPermissionObserver()
        
        if appState.showOnboarding {
            showOnboardingWindow()
        }
        
        logger.info("Quillside 启动完成")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let onboardingWindow, onboardingWindow.isVisible {
            onboardingWindow.makeKeyAndOrderFront(nil)
            return false
        }
        // Keep an active Notes operation in place; reopening must not replace it with settings.
        if NSApp.windows.contains(where: { $0 is NSPanel && $0.isVisible }) { return false }
        Task { @MainActor in SettingsWindowController.shared.show(appState: appState) }
        return false
    }

    private func showOnboardingWindow() {
        let content = OnboardingView(isPresented: Binding(
            get: { [weak self] in self?.appState.showOnboarding ?? false },
            set: { [weak self] visible in
                self?.appState.showOnboarding = visible
                if !visible { self?.onboardingWindow?.close(); self?.onboardingWindow = nil }
            }
        )).environmentObject(appState)
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = "欢迎使用 Quillside"
        window.identifier = NSUserInterfaceItemIdentifier("onboarding")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AIRunRegistry.shared.cancelAll(reason: .shutdown)
        WritingSessionController.shared.persistForTermination()
        NativeNotesAnnotationController.shared.close()
        statusBarController?.stop()
        statusBarController = nil
        logger.info("Quillside 正在退出...")
        stopServices()
        logger.info("Quillside 已退出")
    }
    
    private func checkAccessibilityPermission() {
        let isTrusted = accessibilityBridge.isTrusted
        appState.hasAccessibilityPermission = isTrusted
        
        if isTrusted {
            logger.info("Accessibility 权限已授予")
        } else {
            logger.warning("Accessibility 权限未授予")
        }
    }
    
    private func setupPermissionObserver() {
        Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updatePermissionStatus()
            }
            .store(in: &cancellables)
    }
    
    private func updatePermissionStatus() {
        refreshNotesProcessStatus()
        let isTrusted = accessibilityBridge.isTrusted
        
        if isTrusted != appState.hasAccessibilityPermission {
            appState.hasAccessibilityPermission = isTrusted
            
            if isTrusted {
                logger.info("Accessibility 权限已授予，初始化服务")
                initializeServices()
            } else {
                logger.warning("Accessibility 权限已撤销，停止服务")
                stopServices()
            }
        }

        refreshDatabaseAccessStatus()
        refreshAutomationAccessStatus()
    }

    func refreshPermissionStatus() {
        updatePermissionStatus()
    }
    private func refreshNotesProcessStatus() {
        appState.isNotesRunning = accessibilityBridge.getNotesAppPID() != nil
        appState.isNotesFrontmost = accessibilityBridge.isNotesFrontmost()
    }

    private func refreshAutomationAccessStatus() {
        guard !isRefreshingAutomationAccess else { return }
        isRefreshingAutomationAccess = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status =
                AppleNotesAutomationAccess.shared.currentStatus()
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.isRefreshingAutomationAccess = false
                let displayStatus =
                    AppleNotesAutomationStatus.displayStatus(
                        previous:
                            self.appState.automationAccess,
                        observed: status
                    )
                guard
                    displayStatus
                        != self.appState.automationAccess
                else {
                    return
                }
                self.appState.automationAccess = displayStatus
            }
        }
    }

    private func refreshDatabaseAccessStatus() {
        guard !isRefreshingDatabaseAccess else { return }
        isRefreshingDatabaseAccess = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = NotesDBReader.shared.accessStatus()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRefreshingDatabaseAccess = false
                self.applyDatabaseAccessStatus(status)
            }
        }
    }

    private func applyDatabaseAccessStatus(
        _ status: NotesDatabaseAccessStatus
    ) {
        guard status != appState.notesDatabaseAccess else { return }

        let previousStatus = appState.notesDatabaseAccess
        appState.notesDatabaseAccess = status

        switch NotesDatabaseAccessTransition(from: previousStatus, to: status) {
        case .becameAvailable:
            logger.info("Apple Notes database is available")
            BacklinksService.shared.invalidateCache()
            BacklinksService.shared.buildLinkGraph()
        case .becameUnavailable:
            logger.warning(
                "Apple Notes database status: \(String(describing: status), privacy: .public)"
            )
            NotesDBReader.shared.closeAsync()
            BacklinksService.shared.invalidateCache()
        case .unchanged:
            break
        }
    }
    
    func requestAccessibilityPermission() {
        logger.info("请求 Accessibility 权限")
        accessibilityBridge.requestPermission()
    }
    
    func openAccessibilitySettings() {
        logger.info("打开 Accessibility 设置")
        accessibilityBridge.openAccessibilitySettings()
    }
    
    private func initializeServices() {
        guard windowTracker == nil else {
            logger.debug("服务已初始化，跳过")
            return
        }
        
        logger.info("初始化服务...")
        
        windowTracker = WindowTrackService()
        
        windowTracker?.$isNotesRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.appState.isNotesRunning = value
            }
            .store(in: &serviceCancellables)
        
        windowTracker?.$isNotesFrontmost
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.appState.isNotesFrontmost = value
            }
            .store(in: &serviceCancellables)
        
        windowTracker?.start()
        
        if let tracker = windowTracker {
            floatingBarController = FloatingBarWindowController(windowTracker: tracker)
            Task { @MainActor in NativeNotesAnnotationController.shared.configure(tracker: tracker) }
            
            keyboardMonitor = KeyboardMonitorService()
            keyboardMonitor?.bind(windowTracker: tracker)
            keyboardMonitor?.start()
            
            if let monitor = keyboardMonitor {
                markdownTrigger = MarkdownTriggerService(keyboardMonitor: monitor)
                
                slashCommandService = SlashCommandService(keyboardMonitor: monitor)
                let inputObserver = EditorInputObserver(tracker: tracker, keyboard: monitor)
                editorInputObserver = inputObserver
                inputObserver.changes.sink { [weak self, weak monitor] context in
                    monitor?.updateEditorContext(context)
                    self?.slashCommandService?.observeCommittedInput(context)
                    self?.markdownTrigger?.observeCommittedInput(context)
                }.store(in: &serviceCancellables)
                if let slashService = slashCommandService {
                    slashMenuController = SlashMenuWindowController(slashCommandService: slashService, windowTracker: tracker)
                    slashService.onInsertTemplate = { template, trigger in
                        Task { @MainActor in TemplatePickerController.shared.present(trigger: trigger, direct: template) }
                    }
                    slashService.onShowTemplatePicker = { trigger in
                        Task { @MainActor in TemplatePickerController.shared.present(trigger: trigger) }
                    }
                    Task { @MainActor [weak self, weak slashService] in
                        guard let self, let slashService, self.slashCommandService === slashService else { return }
                        ConfigurationStore.shared.$committed.map(\.templates)
                            .removeDuplicates()
                            .sink { [weak slashService] templates in slashService?.updateTemplates(templates) }
                            .store(in: &self.serviceCancellables)
                    }
                }

                monitor.keyPressSubject
                    .compactMap(\.shortcutAction)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] action in
                        switch action {
                        case .copyMarkdown:
                            self?.performNoteAction(.copyMarkdown)
                        case .copyNoteLink:
                            self?.performNoteAction(.copyNoteLink)
                        case .backlinks:
                            self?.toggleBacklinksPanel()
                        case .askAI:
                            Task { @MainActor in InlineAssistantController.shared.present() }
                        }
                    }
                    .store(in: &serviceCancellables)
            }
            
            noteActionsBarController = NoteActionsBarWindowController(
                windowTracker: tracker
            )

            backlinksPanelController = BacklinksPanelWindowController(
                windowTracker: tracker,
                appState: appState,
                noteActionsFrame: { [weak self] in
                    self?.noteActionsBarController?.actionBarFrame()
                }
            )
            if appState.canUseBacklinks {
                BacklinksService.shared.buildLinkGraph()
            }
            
            noteActionsBarController?.onShowBacklinks = { [weak self] note in
                self?.backlinksPanelController?.show(note: note)
            }
        }

        logger.info("服务初始化完成")
    }
    
    private func stopServices() {
        logger.info("停止服务...")
        Task { @MainActor in NativeNotesAnnotationController.shared.configure(tracker: nil) }
        
        serviceCancellables.removeAll()
        
        noteActionsBarController?.hide()
        noteActionsBarController = nil
        
        backlinksPanelController?.hide()
        backlinksPanelController = nil
        
        slashMenuController?.hide()
        slashMenuController = nil
        slashCommandService = nil
        
        markdownTrigger = nil
        
        keyboardMonitor?.stop()
        keyboardMonitor = nil
        editorInputObserver = nil
        
        floatingBarController?.hide()
        floatingBarController = nil
        
        windowTracker?.stop()
        windowTracker = nil
        
        logger.info("服务已停止")
    }
    
    func toggleBacklinksPanel() {
        backlinksPanelController?.toggle()
    }

    func performNoteAction(_ action: NoteActionKind) {
        noteActionsBarController?.performFromMenu(action)
    }
}
