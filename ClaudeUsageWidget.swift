import Cocoa
import WebKit

// ── Config ──────────────────────────────────────────────────────────────
let ORG_ID = ProcessInfo.processInfo.environment["CLAUDE_ORG_ID"] ?? "d93fb657-add2-414d-9493-a50dea6180b4"
let USAGE_URL = "https://claude.ai/api/organizations/\(ORG_ID)/usage"
let CLAUDE_URL = "https://claude.ai"
let REFRESH_INTERVAL: TimeInterval = 60
let WIDGET_WIDTH: CGFloat = 340
let WIDGET_MARGIN: CGFloat = 16
let USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

// ── Data Models ─────────────────────────────────────────────────────────
struct UsageData {
    var fiveHourPct: Double = 0; var fiveHourReset = ""
    var sevenDayPct: Double = 0; var sevenDayReset = ""
    var sevenDaySonnetPct: Double = 0; var sevenDaySonnetReset = ""
    var hasSonnet = false
}

struct CcusageData {
    var todayCost: Double = 0; var todayTokens = 0
    var todayModels: [(name: String, cost: Double)] = []
    var monthCost: Double = 0; var monthTokens = 0
    var monthModels: [(name: String, cost: Double)] = []
    var dailyEntries: [(day: String, cost: Double)] = []
    var monthInput = 0; var monthOutput = 0
    var monthCacheWrite = 0; var monthCacheRead = 0
}

// ── Navigator: hidden WKWebView that navigates to pages and reads content
class PageNavigator: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    var onContent: ((String) -> Void)?
    var onLoginNeeded: (() -> Void)?
    private var retryCount = 0
    private var popupWebViews: [WKWebView] = []
    private var popupWindows: [NSWindowController] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = USER_AGENT
    }

    func navigate(to url: String, completion: @escaping (String) -> Void) {
        onContent = completion
        retryCount = 0
        webView.load(URLRequest(url: URL(string: url)!))
    }

    func webView(_ wv: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            wv.evaluateJavaScript("document.body.innerText") { result, _ in
                let text = result as? String ?? ""
                if text.contains("utilization") {
                    self.onContent?(text)
                } else if text.contains("permission_error") || text.contains("session_invalid") || wv.url?.absoluteString.contains("/login") == true {
                    self.onLoginNeeded?()
                } else if text.contains("moment") || text.contains("확인") {
                    self.retryCount += 1
                    if self.retryCount < 5 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { wv.reload() }
                    } else { self.onContent?("") }
                } else if wv.url?.absoluteString != USAGE_URL {
                    wv.load(URLRequest(url: URL(string: USAGE_URL)!))
                } else {
                    self.onContent?("")
                }
            }
        }
    }

    // ── OAuth popup support ─────────────────────────────────────────────
    func webView(_ wv: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 650),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        win.title = "Login"; win.center()
        let popup = WKWebView(frame: win.contentView!.bounds, configuration: configuration)
        popup.autoresizingMask = [.width, .height]
        popup.uiDelegate = self
        popup.customUserAgent = wv.customUserAgent
        win.contentView?.addSubview(popup)
        let wc = NSWindowController(window: win)
        popupWindows.append(wc); popupWebViews.append(popup)
        wc.showWindow(nil)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let idx = self.popupWebViews.firstIndex(where: { $0 === webView }) {
                self.popupWindows[idx].window?.orderOut(nil)
                self.popupWebViews.remove(at: idx)
                self.popupWindows.remove(at: idx)
            }
        }
    }

    func cleanupPopups() {
        for wc in popupWindows { wc.window?.orderOut(nil) }
        popupWebViews.removeAll(); popupWindows.removeAll()
    }
}

// ── Script Message Handler (prevent WKUserContentController retain cycle)
class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: AppDelegate?
    init(delegate: AppDelegate) { self.delegate = delegate }
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        if let h = message.body as? Double {
            delegate?.resizeWidget(height: CGFloat(h))
        } else if let action = message.body as? String {
            switch action {
            case "refresh": delegate?.refreshNow()
            case "logout": delegate?.logout()
            case "login": delegate?.openLoginWindow()
            default: break
            }
        }
    }
}

// ── App Delegate ────────────────────────────────────────────────────────
class AppDelegate: NSObject, NSApplicationDelegate {
    private var scriptMessageHandler: WeakScriptMessageHandler!
    private var widgetWindow: NSWindow!
    private var widgetWebView: WKWebView!
    private var loginWindow: NSWindow?
    private var navigator: PageNavigator!
    private var refreshTimer: Timer?
    private var loginPollTimer: Timer?
    private var usageData = UsageData()
    private var ccusageData = CcusageData()
    private var isLoggedIn = false
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        navigator = PageNavigator()
        navigator.onLoginNeeded = { [weak self] in self?.openLoginWindow() }
        setupStatusBar()
        setupWidgetWindow()
        fetchAll()
    }

    // ── Status Bar ──────────────────────────────────────────────────────
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "◆"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Widget", action: #selector(showWidget), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide Widget", action: #selector(hideWidget), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Logout", action: #selector(logout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func showWidget() { widgetWindow.orderFront(nil) }
    @objc func hideWidget() { widgetWindow.orderOut(nil) }
    @objc func refreshNow() { fetchAll() }
    private var lastWidgetHeight: CGFloat = 0
    func resizeWidget(height: CGFloat) {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let h = min(max(height + 2, 200), sf.height - WIDGET_MARGIN * 2)
        guard abs(h - lastWidgetHeight) > 2 else { return } // skip if no real change
        lastWidgetHeight = h
        var frame = widgetWindow.frame
        let oldTop = frame.origin.y + frame.size.height
        frame.size.height = h
        frame.origin.y = oldTop - h
        widgetWindow.setFrame(frame, display: true, animate: false)
    }
    @objc func logout() {
        stopRefreshTimer()
        isLoggedIn = false; usageData = UsageData()
        updateWidgetHTML()
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            self.navigator = PageNavigator()
            self.navigator.onLoginNeeded = { [weak self] in self?.openLoginWindow() }
            self.openLoginWindow()
        }
    }
    @objc func quitApp() { NSApp.terminate(nil) }

    // ── Refresh Timer ───────────────────────────────────────────────────
    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: REFRESH_INTERVAL, repeats: true) { [weak self] _ in
            self?.fetchAll()
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate(); refreshTimer = nil
    }

    // ── Widget Window ───────────────────────────────────────────────────
    private func setupWidgetWindow() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let h: CGFloat = 300 // initial height, auto-resizes to content
        widgetWindow = NSWindow(
            contentRect: NSRect(x: sf.maxX - WIDGET_WIDTH - WIDGET_MARGIN, y: sf.maxY - h - WIDGET_MARGIN, width: WIDGET_WIDTH, height: h),
            styleMask: [.borderless], backing: .buffered, defer: false)
        widgetWindow.isOpaque = false; widgetWindow.backgroundColor = .clear
        widgetWindow.level = .floating
        widgetWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        widgetWindow.isMovableByWindowBackground = true; widgetWindow.hasShadow = true

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        scriptMessageHandler = WeakScriptMessageHandler(delegate: self)
        config.userContentController.add(scriptMessageHandler!, name: "widget")
        widgetWebView = WKWebView(frame: widgetWindow.contentView!.bounds, configuration: config)
        widgetWebView.autoresizingMask = [.width, .height]
        widgetWebView.setValue(false, forKey: "drawsBackground")
        widgetWindow.contentView?.addSubview(widgetWebView)
        updateWidgetHTML()
        widgetWindow.orderFront(nil)
    }

    // ── Data Fetching ───────────────────────────────────────────────────
    private func fetchAll() {
        fetchUsage()
        fetchCcusage()
    }

    private func fetchUsage() {
        navigator.navigate(to: USAGE_URL) { [weak self] text in
            guard let self = self, !text.isEmpty else { return }
            self.isLoggedIn = true
            self.parseUsageJSON(text)
            self.updateWidgetHTML()
            self.startRefreshTimer()
        }
    }

    // ── Login Window ────────────────────────────────────────────────────
    func openLoginWindow() {
        if let w = loginWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        win.title = "Claude Login"; win.center()
        navigator.webView.frame = win.contentView!.bounds
        navigator.webView.autoresizingMask = [.width, .height]
        win.contentView?.addSubview(navigator.webView)
        navigator.webView.load(URLRequest(url: URL(string: "\(CLAUDE_URL)/login")!))
        loginWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startLoginPoll()
    }

    private func closeLoginWindow() {
        navigator.cleanupPopups()
        navigator.webView.removeFromSuperview()
        loginWindow?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.loginWindow?.close()
            self?.loginWindow = nil
        }
    }

    private func startLoginPoll() {
        loginPollTimer?.invalidate()
        let probeConfig = WKWebViewConfiguration()
        probeConfig.websiteDataStore = .default()
        let probe = WKWebView(frame: .zero, configuration: probeConfig)
        probe.customUserAgent = USER_AGENT

        var probing = false
        loginPollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self = self, self.loginWindow != nil, !probing else {
                if self?.loginWindow == nil { self?.loginPollTimer?.invalidate() }
                return
            }
            probing = true
            probe.load(URLRequest(url: URL(string: USAGE_URL)!))
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                probe.evaluateJavaScript("document.body.innerText") { result, _ in
                    probing = false
                    let text = result as? String ?? ""
                    guard text.contains("utilization") else { return }
                    self.loginPollTimer?.invalidate()
                    self.closeLoginWindow()
                    // Fresh navigator for post-login fetches
                    self.navigator = PageNavigator()
                    self.navigator.onLoginNeeded = { [weak self] in self?.openLoginWindow() }
                    self.isLoggedIn = true
                    self.parseUsageJSON(text)
                    self.updateWidgetHTML()
                    self.startRefreshTimer()
                    self.fetchCcusage()
                }
            }
        }
    }

    // ── ccusage ─────────────────────────────────────────────────────────
    private func fetchCcusage() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let weekAgo = self.sh("/bin/date", ["-v-6d", "+%Y%m%d"])
            let monthStart = self.sh("/bin/date", ["+%Y%m01"])
            let today = self.dateStr("yyyy-MM-dd")
            let npx = self.findExecutable("npx") ?? "/opt/homebrew/bin/npx"
            let daily = self.sh(npx, ["--yes", "ccusage", "daily", "--since", weekAgo, "--json", "--breakdown"])
            let monthly = self.sh(npx, ["--yes", "ccusage", "monthly", "--since", monthStart, "--json", "--breakdown"])
            self.parseCcusageDaily(daily, today: today)
            self.parseCcusageMonthly(monthly)
            DispatchQueue.main.async { self.updateWidgetHTML() }
        }
    }

    // ── Parsing ─────────────────────────────────────────────────────────
    private func parseUsageJSON(_ json: String) {
        guard let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        func extract(_ key: String) -> (Double, String) {
            guard let v = o[key] as? [String: Any] else { return (0, "") }
            return (v["utilization"] as? Double ?? 0, v["resets_at"] as? String ?? "")
        }
        (usageData.fiveHourPct, usageData.fiveHourReset) = extract("five_hour")
        (usageData.sevenDayPct, usageData.sevenDayReset) = extract("seven_day")
        (usageData.sevenDaySonnetPct, usageData.sevenDaySonnetReset) = extract("seven_day_sonnet")
        usageData.hasSonnet = usageData.sevenDaySonnetPct > 0
    }

    private func parseCcusageDaily(_ json: String, today: String) {
        guard let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let arr = o["daily"] as? [[String: Any]] else { return }
        ccusageData.dailyEntries = []
        for e in arr {
            let date = e["date"] as? String ?? ""
            let cost = e["totalCost"] as? Double ?? 0
            ccusageData.dailyEntries.append((day: dayLabel(date), cost: cost))
            if date == today {
                ccusageData.todayCost = cost
                ccusageData.todayTokens = e["totalTokens"] as? Int ?? 0
                ccusageData.todayModels = (e["modelBreakdowns"] as? [[String: Any]] ?? []).map {
                    (name: shortModel($0["modelName"] as? String ?? ""), cost: $0["cost"] as? Double ?? 0)
                }
            }
        }
    }

    private func parseCcusageMonthly(_ json: String) {
        guard let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let t = o["totals"] as? [String: Any] else { return }
        ccusageData.monthCost = t["totalCost"] as? Double ?? 0
        ccusageData.monthTokens = t["totalTokens"] as? Int ?? 0
        ccusageData.monthInput = t["inputTokens"] as? Int ?? 0
        ccusageData.monthOutput = t["outputTokens"] as? Int ?? 0
        ccusageData.monthCacheWrite = t["cacheCreationTokens"] as? Int ?? 0
        ccusageData.monthCacheRead = t["cacheReadTokens"] as? Int ?? 0
        var mm: [String: Double] = [:]
        for m in (o["monthly"] as? [[String: Any]] ?? []) {
            for b in (m["modelBreakdowns"] as? [[String: Any]] ?? []) {
                mm[shortModel(b["modelName"] as? String ?? ""), default: 0] += b["cost"] as? Double ?? 0
            }
        }
        ccusageData.monthModels = mm.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    // ── Helpers ──────────────────────────────────────────────────────────
    private func sh(_ cmd: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: cmd); p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    private func findExecutable(_ name: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
    private func dateStr(_ f: String) -> String { let d = DateFormatter(); d.dateFormat = f; return d.string(from: Date()) }
    private func dayLabel(_ s: String) -> String {
        let d = DateFormatter(); d.dateFormat = "yyyy-MM-dd"
        guard let dt = d.date(from: s) else { return "?" }
        return ["일","월","화","수","목","금","토"][Calendar.current.component(.weekday, from: dt) - 1]
    }
    private func shortModel(_ n: String) -> String {
        n.replacingOccurrences(of: "claude-", with: "").replacingOccurrences(of: #"-20\d{6}"#, with: "", options: .regularExpression)
    }
    private func fc(_ c: Double) -> String { c >= 100 ? String(format:"%.0f",c) : c >= 10 ? String(format:"%.1f",c) : String(format:"%.2f",c) }
    private func ft(_ n: Int) -> String { n >= 1_000_000 ? String(format:"%.1fM",Double(n)/1e6) : n >= 1_000 ? "\(n/1000)K" : "\(n)" }
    private func fr(_ iso: String) -> String {
        let d = ISO8601DateFormatter(); d.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let dt = d.date(from: iso) else { return "" }
        let s = dt.timeIntervalSinceNow; if s <= 0 { return "곧 리셋" }
        let h = Int(s)/3600, m = (Int(s)%3600)/60
        return h > 0 ? "\(h)시간 \(m)분 후 리셋" : "\(m)분 후 리셋"
    }
    private func bc(_ p: Double) -> String { p >= 90 ? "#ef4444" : p >= 70 ? "#f59e0b" : "#a78bfa" }
    private func pc(_ p: Double) -> String { p >= 90 ? "#fca5a5" : p >= 70 ? "#fcd34d" : "#e4e4e7" }

    // ── Widget HTML ─────────────────────────────────────────────────────
    func updateWidgetHTML() {
        let t = dateStr("HH:mm")
        let mx = max(ccusageData.dailyEntries.map{$0.cost}.max() ?? 0.01, 0.01)
        var bars = ""
        for (i,e) in ccusageData.dailyEntries.enumerated() {
            let p = max((e.cost/mx)*100,3); let last = i == ccusageData.dailyEntries.count-1
            let bg = last ? "linear-gradient(to top,#7c3aed,#a78bfa)" : "linear-gradient(to top,rgba(167,139,250,0.3),rgba(167,139,250,0.5))"
            bars += "<div class='bw'><div class='b' style='height:\(p)%;background:\(bg)'></div><span class='bl'>\(e.day)</span></div>"
        }
        var tm = "", mm = ""
        for m in ccusageData.todayModels { tm += "<div class='mr'><span class='mn'>\(m.name)</span><span class='mc'>$\(fc(m.cost))</span></div>" }
        for m in ccusageData.monthModels { mm += "<div class='mr'><span class='mn'>\(m.name)</span><span class='mc'>$\(fc(m.cost))</span></div>" }
        func pb(_ l:String,_ p:Double,_ r:String)->String{
            "<div class='pr'><div class='ph'><span class='pl'>\(l)</span><span class='pp' style='color:\(pc(p))'>\(Int(p))%</span></div><div class='pbg'><div class='pf' style='width:\(min(p,100))%;background:\(bc(p))'></div></div><div class='rl'>\(fr(r))</div></div>"
        }
        let rl = isLoggedIn ? """
        <div class='s'><div class='st'>Rate Limits</div>
        \(pb("7일 전체",usageData.sevenDayPct,usageData.sevenDayReset))
        \(pb("5시간",usageData.fiveHourPct,usageData.fiveHourReset))
        \(usageData.hasSonnet ? pb("7일 Sonnet",usageData.sevenDaySonnetPct,usageData.sevenDaySonnetReset) : "")
        </div>
        """ : "<div class='nd'>◆ 메뉴바에서 로그인하세요</div>"

        let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        *{margin:0;padding:0;box-sizing:border-box}
        body{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;font-size:12px;color:#e4e4e7;
        background:rgba(24,24,27,0.88);border:1px solid rgba(255,255,255,0.08);border-radius:16px;padding:16px;
        -webkit-user-select:none;cursor:default;overflow:hidden}
        .hd{display:flex;justify-content:space-between;align-items:center;margin-bottom:14px}
        .ti{font-size:14px;font-weight:600;color:#f4f4f5}.bg{font-size:10px;font-weight:500;color:#a78bfa;background:rgba(167,139,250,0.12);padding:2px 8px;border-radius:6px}
        .tm{font-size:10px;color:#71717a;margin-left:8px}.s{margin-bottom:12px}
        .st{font-size:10px;font-weight:600;color:#a1a1aa;text-transform:uppercase;letter-spacing:.05em;margin-bottom:8px}
        .dv{height:1px;background:rgba(255,255,255,0.06);margin:12px 0}
        .cb{font-size:24px;font-weight:700;color:#f4f4f5}.sl{color:#a1a1aa;font-size:11px}
        .rw{display:flex;justify-content:space-between;align-items:baseline}
        .mr{display:flex;justify-content:space-between;padding:5px 8px;background:rgba(255,255,255,0.03);border-radius:8px;margin-bottom:4px}
        .mn{font-size:11px;color:#d4d4d8;font-weight:500}.mc{font-size:11px;color:#a78bfa;font-weight:600}
        .ch{display:flex;align-items:flex-end;gap:4px;height:48px;padding:4px 0}
        .bw{display:flex;flex-direction:column;align-items:center;flex:1;gap:4px}
        .b{width:100%;border-radius:3px 3px 1px 1px;min-height:2px}.bl{font-size:9px;color:#71717a}
        .tr{display:flex;justify-content:space-between;padding:3px 0}.tl{font-size:10px;color:#71717a}.tv{font-size:10px;color:#a1a1aa;font-weight:500}
        .pr{margin-bottom:10px}.ph{display:flex;justify-content:space-between;margin-bottom:4px}
        .pl{font-size:11px;color:#a1a1aa;font-weight:500}.pp{font-size:12px;font-weight:700}
        .pbg{width:100%;height:6px;background:rgba(255,255,255,0.06);border-radius:3px;overflow:hidden}
        .pf{height:100%;border-radius:3px;transition:width .5s}
        .rl{font-size:9px;color:#52525b;margin-top:3px;text-align:right}
        .nd{color:#71717a;font-size:11px;text-align:center;padding:8px 0}
        .btns{display:flex;gap:8px;margin-top:4px;padding-top:12px;border-top:1px solid rgba(255,255,255,0.06)}
        .btn{flex:1;padding:8px 0;border:none;border-radius:8px;font-size:11px;font-weight:600;cursor:pointer;
        font-family:inherit;transition:opacity .15s}
        .btn:active{opacity:0.7}
        .btn-ref{background:rgba(167,139,250,0.15);color:#a78bfa}
        .btn-auth{background:rgba(239,68,68,0.12);color:#f87171}
        .btn-auth.login{background:rgba(167,139,250,0.15);color:#a78bfa}
        </style></head><body>
        <div class='hd'><span class='ti'>◆ Claude Usage</span><div><span class='bg'>Max 20x</span><span class='tm'>\(t)</span></div></div>
        \(rl)<div class='dv'></div>
        <div class='s'><div class='st'>Today</div>
        <div class='rw'><span class='cb'>$\(fc(ccusageData.todayCost))</span><span class='sl'>\(ft(ccusageData.todayTokens)) tokens</span></div>
        \(tm.isEmpty ? "" : "<div style='margin-top:6px'>\(tm)</div>")</div>
        <div class='dv'></div>
        \(ccusageData.dailyEntries.isEmpty ? "" : "<div class='s'><div class='st'>Last 7 Days</div><div class='ch'>\(bars)</div></div><div class='dv'></div>")
        <div class='s'><div class='st'>This Month</div>
        <div class='rw' style='margin-bottom:8px'><span class='cb'>$\(fc(ccusageData.monthCost))</span><span class='sl'>\(ft(ccusageData.monthTokens)) tokens</span></div>
        <div style='margin-bottom:8px'>
        <div class='tr'><span class='tl'>Input</span><span class='tv'>\(ft(ccusageData.monthInput))</span></div>
        <div class='tr'><span class='tl'>Output</span><span class='tv'>\(ft(ccusageData.monthOutput))</span></div>
        <div class='tr'><span class='tl'>Cache Write</span><span class='tv'>\(ft(ccusageData.monthCacheWrite))</span></div>
        <div class='tr'><span class='tl'>Cache Read</span><span class='tv'>\(ft(ccusageData.monthCacheRead))</span></div>
        </div>\(mm)</div>
        <div class='btns'>
        <button class='btn btn-ref' onclick="webkit.messageHandlers.widget.postMessage('refresh')">↻ Refresh</button>
        <button class='btn btn-auth \(isLoggedIn ? "" : "login")' onclick="webkit.messageHandlers.widget.postMessage('\(isLoggedIn ? "logout" : "login")')">\(isLoggedIn ? "Logout" : "Login")</button>
        </div>
        <script>window.onload=()=>{webkit.messageHandlers.widget.postMessage(document.body.scrollHeight)}</script>
        </body></html>
        """
        widgetWebView.loadHTMLString(html, baseURL: nil)
    }
}

// ── Main ────────────────────────────────────────────────────────────────
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate

// App menu with Cmd+Q
let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(NSMenuItem(title: "About Claude Usage", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(NSMenuItem(title: "Quit Claude Usage", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
appMenuItem.submenu = appMenu
app.mainMenu = mainMenu

app.run()
