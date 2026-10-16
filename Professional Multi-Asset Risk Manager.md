//@version=6
indicator("Professional Multi-Asset Risk Manager [VN]", "Risk Manager Pro VN", overlay = true, max_lines_count = 20, max_labels_count = 20)

// ============================================================================
// PROFESSIONAL MULTI-ASSET POSITION SIZE & RISK CALCULATOR
// Stocks · Forex · Futures/Commodities · Crypto
//
// Đây là công cụ lập kế hoạch và tính quy mô vị thế, không phải tín hiệu mua/bán.
// Chỉ báo không thể đọc trực tiếp số dư/margin của tài khoản broker.
// Luôn đối chiếu point value, bước khối lượng và margin với broker/sàn của bạn.
// ============================================================================

// ---------- Helpers ----------
f_floor_step(float value, float step) =>
    not na(value) and step > 0 ? math.floor((value + step * 1e-10) / step) * step : na

f_floor_tick(float value) =>
    not na(value) and syminfo.mintick > 0 ? math.floor((value + syminfo.mintick * 1e-10) / syminfo.mintick) * syminfo.mintick : na

f_ceil_tick(float value) =>
    not na(value) and syminfo.mintick > 0 ? math.ceil((value - syminfo.mintick * 1e-10) / syminfo.mintick) * syminfo.mintick : na

f_money(float value) =>
    na(value) ? "N/A" : math.abs(value) >= 100 ? str.format("{0,number,#,###.##}", value) : math.abs(value) >= 1 ? str.format("{0,number,#,###.####}", value) : str.format("{0,number,#,###.########}", value)

f_qty(float value) =>
    na(value) ? "N/A" : str.format("{0,number,#,###.########}", value)

f_price(float value) =>
    na(value) ? "N/A" : str.tostring(value, format.mintick)

f_pct(float value) =>
    na(value) ? "N/A" : str.format("{0,number,#.###}%", value)

f_append(string base, string message) =>
    base == "" ? "• " + message : base + "\n• " + message

f_row(table panel, int row, string key, string value, color valueColor, color rowBg) =>
    table.cell(panel, 0, row, key, text_color = color.rgb(170, 181, 199), bgcolor = rowBg, text_halign = text.align_left, text_size = size.small)
    table.cell(panel, 1, row, value, text_color = valueColor, bgcolor = rowBg, text_halign = text.align_right, text_size = size.small)

f_set_line(line id, int x1, int x2, float y, color lineColor) =>
    line.set_xy1(id, x1, y)
    line.set_xy2(id, x2, y)
    line.set_color(id, lineColor)

f_hide_line(line id) =>
    line.set_color(id, color.new(color.gray, 100))

f_set_label(label id, int x, float y, string labelText, color labelColor) =>
    label.set_xy(id, x, y)
    label.set_text(id, labelText)
    label.set_color(id, labelColor)
    label.set_textcolor(id, color.white)

f_hide_label(label id) =>
    label.set_text(id, "")
    label.set_color(id, color.new(color.black, 100))

// ---------- Input groups ----------
string G_ACCOUNT = "1 · Tài khoản & ngân sách rủi ro"
string G_PLAN    = "2 · Kế hoạch giao dịch"
string G_TARGETS = "3 · Chốt lời & chia khối lượng"
string G_MODEL   = "4 · Mô hình sản phẩm & khối lượng"
string G_COSTS   = "5 · Phí, spread & trượt giá"
string G_LIMITS  = "6 · Margin & giới hạn vị thế"
string G_DISPLAY = "7 · Hiển thị & cảnh báo"

// ---------- 1. Account & risk budget ----------
float accountEquity = input.float(10000.0, "Vốn tài khoản", minval = 0.01, step = 100.0, group = G_ACCOUNT,
     tooltip = "Nhập equity/balance hiện tại. Chỉ báo không đọc được số dư broker.")
string accountCurrencyInput = input.string("USD", "Tiền tệ tài khoản", group = G_ACCOUNT,
     tooltip = "Mã tiền tệ viết hoa, ví dụ USD, EUR, GBP, JPY, VND. Nếu tỷ giá tự động không có, chọn chế độ thủ công.")
string accountCurrency = str.upper(str.trim(accountCurrencyInput))
string riskMode = input.string("% vốn", "Cách đặt rủi ro", options = ["% vốn", "Số tiền cố định"], group = G_ACCOUNT)
float riskPercent = input.float(1.0, "Rủi ro mỗi lệnh (%)", minval = 0.01, maxval = 100.0, step = 0.05, group = G_ACCOUNT, active = riskMode == "% vốn")
float fixedRiskCash = input.float(100.0, "Rủi ro cố định", minval = 0.01, step = 10.0, group = G_ACCOUNT, active = riskMode == "Số tiền cố định")
bool usePortfolioCap = input.bool(false, "Giới hạn tổng rủi ro danh mục", group = G_ACCOUNT)
float portfolioRiskCapPct = input.float(5.0, "Tổng rủi ro tối đa (%)", minval = 0.01, maxval = 100.0, step = 0.25, group = G_ACCOUNT, active = usePortfolioCap)
float currentOpenRiskCash = input.float(0.0, "Rủi ro đang mở", minval = 0.0, step = 10.0, group = G_ACCOUNT, active = usePortfolioCap)
string fxMode = input.string("Tự động (tỷ giá ngày)", "Quy đổi tiền tệ", options = ["Tự động (tỷ giá ngày)", "Thủ công"], group = G_ACCOUNT)
float manualFxRate = input.float(1.0, "1 đơn vị quote = ? tiền tài khoản", minval = 0.00000001, step = 0.0001, group = G_ACCOUNT, active = fxMode == "Thủ công")

// ---------- 2. Trade plan ----------
string side = input.string("Long", "Hướng giao dịch", options = ["Long", "Short"], group = G_PLAN)
string entryMode = input.string("Giá hiện tại", "Entry", options = ["Giá hiện tại", "Giá thủ công"], group = G_PLAN)
float manualEntryInput = input.price(0.0, "Giá Entry thủ công", group = G_PLAN,
     tooltip = "Chọn Entry = Giá thủ công để dùng mức này. Có thể kéo marker giá trên biểu đồ.", active = entryMode == "Giá thủ công")
string stopMode = input.string("% từ Entry", "Cách đặt Stop", options = ["Giá thủ công", "% từ Entry", "ATR", "Số tick"], group = G_PLAN)
float manualStopInput = input.price(0.0, "Giá Stop thủ công", group = G_PLAN,
     tooltip = "Chọn Stop = Giá thủ công để dùng mức này. Có thể kéo marker giá trên biểu đồ.", active = stopMode == "Giá thủ công")
float stopPercent = input.float(2.0, "Khoảng Stop (%)", minval = 0.0001, maxval = 100.0, step = 0.1, group = G_PLAN, active = stopMode == "% từ Entry")
int atrLength = input.int(14, "ATR length", minval = 1, maxval = 500, group = G_PLAN, active = stopMode == "ATR")
float atrMultiple = input.float(2.0, "ATR multiplier", minval = 0.01, maxval = 100.0, step = 0.1, group = G_PLAN, active = stopMode == "ATR")
float stopTicks = input.float(100.0, "Khoảng Stop (tick)", minval = 1.0, step = 1.0, group = G_PLAN, active = stopMode == "Số tick")
bool allowNonStandardChart = input.bool(false, "Cho phép chart phi tiêu chuẩn", group = G_PLAN,
     tooltip = "Heikin-Ashi, Renko, Range, Kagi... dùng giá tổng hợp. Mặc định chỉ báo khóa sizing trên các chart này.")

// ---------- 3. Targets & partial exits ----------
string targetMode = input.string("Theo R", "Cách đặt TP", options = ["Theo R", "Giá thủ công"], group = G_TARGETS)
float tp1R = input.float(1.0, "TP1 (R)", minval = 0.01, maxval = 100.0, step = 0.25, group = G_TARGETS, active = targetMode == "Theo R")
float tp2R = input.float(2.0, "TP2 (R)", minval = 0.01, maxval = 100.0, step = 0.25, group = G_TARGETS, active = targetMode == "Theo R")
float tp3R = input.float(3.0, "TP3 (R)", minval = 0.01, maxval = 100.0, step = 0.25, group = G_TARGETS, active = targetMode == "Theo R")
float manualTp1Input = input.price(0.0, "Giá TP1 thủ công", group = G_TARGETS, active = targetMode == "Giá thủ công")
float manualTp2Input = input.price(0.0, "Giá TP2 thủ công", group = G_TARGETS, active = targetMode == "Giá thủ công")
float manualTp3Input = input.price(0.0, "Giá TP3 thủ công", group = G_TARGETS, active = targetMode == "Giá thủ công")
float tp1AllocationPct = input.float(100.0, "Khối lượng thoát tại TP1 (%)", minval = 0.0, maxval = 100.0, step = 1.0, group = G_TARGETS,
     tooltip = "Mặc định thoát toàn bộ tại TP1 để kế hoạch 1 contract vẫn thực thi được. Giảm tỷ lệ này khi muốn chia nhiều TP.")
float tp2AllocationPct = input.float(0.0, "Khối lượng thoát tại TP2 (%)", minval = 0.0, maxval = 100.0, step = 1.0, group = G_TARGETS,
     tooltip = "TP3 tự nhận phần còn lại. Tổng TP1 + TP2 phải không vượt 100%.")

// ---------- 4. Product/P&L model ----------
string pnlModel = input.string("Auto Linear", "Mô hình P&L", options = ["Auto Linear", "Manual Value/Point", "Manual Tick Value", "Direct Loss/Qty"], group = G_MODEL,
     tooltip = "Auto Linear: cổ phiếu, spot, futures và linear perpetual khi metadata đúng. Manual Value/Point: forex lot/CFD. Manual Tick Value: hợp đồng có tick value công bố. Direct Loss/Qty: inverse/quanto hoặc sản phẩm đặc thù.")
float manualPointValue = input.float(1.0, "Giá trị quote / biến động 1.0 / qty", minval = 0.00000001, step = 0.01, group = G_MODEL, active = pnlModel == "Manual Value/Point")
float manualTickValue = input.float(1.0, "Giá trị 1 tick / qty", minval = 0.00000001, step = 0.01, group = G_MODEL, active = pnlModel == "Manual Tick Value")
string tickValueCurrency = input.string("Quote", "Tiền tệ của tick value", options = ["Quote", "Account"], group = G_MODEL, active = pnlModel == "Manual Tick Value")
float directLossPerQty = input.float(1.0, "Lỗ tại Stop / qty (tiền tài khoản)", minval = 0.00000001, step = 0.01, group = G_MODEL,
     tooltip = "Dùng cho inverse/quanto hoặc sản phẩm phi tuyến. Nhập lỗ do biến động giá + execution buffer cho 1 qty tại Stop; phí tiền mặt được cộng riêng bên dưới.", active = pnlModel == "Direct Loss/Qty")
bool useAutoQtyRules = input.bool(false, "Tự động bước/min khối lượng", group = G_MODEL,
     tooltip = "Dùng syminfo.mincontract. Feed TradingView có thể khác quy định broker; tắt để nhập thủ công.")
float manualQtyStep = input.float(1.0, "Bước khối lượng broker", minval = 0.00000001, step = 0.01, group = G_MODEL, active = not useAutoQtyRules)
float manualMinQty = input.float(1.0, "Khối lượng tối thiểu", minval = 0.00000001, step = 0.01, group = G_MODEL, active = not useAutoQtyRules)
float qtyPerLot = input.float(100000.0, "Native qty trong 1 lot", minval = 0.00000001, step = 1.0, group = G_MODEL,
     tooltip = "Forex theo base units thường dùng 100,000. Nếu qty của mô hình đã là lot, nhập 1.")
string qtyUnitInput = input.string("Native qty", "Tên đơn vị khối lượng", options = ["Native qty", "Units", "Lots", "Contracts", "Shares", "Coins"], group = G_MODEL,
     tooltip = "Chọn đúng đơn vị mà mô hình/broker dùng. Mặc định giữ nhãn trung tính để tránh nhầm units, lots và contracts.")
float manualNotionalPerQty = input.float(0.0, "Notional / qty (tiền tài khoản)", minval = 0.0, step = 1.0, group = G_MODEL,
     tooltip = "Trong Direct Loss/Qty, giá trị này chỉ dùng để tham khảo notional/margin. Hãy dùng phí tiền mặt/qty và margin/qty thủ công. 0 = chưa biết.", active = pnlModel == "Direct Loss/Qty")

// ---------- 5. Costs ----------
float adverseTicks = input.float(0.0, "Tổng tick bất lợi (không dùng cho Direct)", minval = 0.0, step = 0.25, group = G_COSTS,
     tooltip = "Tổng buffer round-trip cho spread + slippage + gap nhỏ. Được cộng vào khoảng lỗ và trừ khỏi khoảng lời. Với Direct Loss/Qty, phải đặt trường này = 0 và tự gộp buffer vào Direct Loss.")
float cashFeePerQtyRT = input.float(0.0, "Phí tiền mặt / qty / round-trip", minval = 0.0, step = 0.01, group = G_COSTS)
float feePercentPerSide = input.float(0.0, "Phí % notional / mỗi chiều", minval = 0.0, maxval = 100.0, step = 0.001, group = G_COSTS,
     tooltip = "Ví dụ phí taker 0.05% thì nhập 0.05.")
float fixedFeeRoundTrip = input.float(0.0, "Phí cố định toàn lệnh", minval = 0.0, step = 0.01, group = G_COSTS,
     tooltip = "Phí cố định dự kiến cho toàn bộ entry + các lệnh thoát.")

// ---------- 6. Margin and caps ----------
string marginModel = input.string("Notional / đòn bẩy", "Mô hình margin", options = ["Notional / đòn bẩy", "Margin / qty thủ công"], group = G_LIMITS)
float leverage = input.float(1.0, "Đòn bẩy", minval = 0.01, maxval = 1000.0, step = 0.5, group = G_LIMITS)
float manualMarginPerQty = input.float(0.0, "Margin / qty", minval = 0.0, step = 1.0, group = G_LIMITS,
     tooltip = "Hữu ích cho futures vì margin thực tế không nhất thiết bằng notional / leverage.", active = marginModel == "Margin / qty thủ công")
bool useMarginCap = input.bool(false, "Giới hạn theo margin khả dụng", group = G_LIMITS)
float availableMargin = input.float(10000.0, "Margin khả dụng", minval = 0.0, step = 100.0, group = G_LIMITS, active = useMarginCap)
float maxMarginUsePct = input.float(100.0, "Tối đa dùng margin (%)", minval = 0.01, maxval = 100.0, step = 1.0, group = G_LIMITS, active = useMarginCap)
float maxQtyInput = input.float(0.0, "Khối lượng tối đa (0 = không giới hạn)", minval = 0.0, step = 1.0, group = G_LIMITS)
float minNotionalInput = input.float(0.0, "Notional tối thiểu (0 = tắt)", minval = 0.0, step = 1.0, group = G_LIMITS,
     tooltip = "Giá trị lệnh tối thiểu theo tiền tài khoản. Nếu không đạt, chỉ báo trả NO TRADE và không tự nâng qty.")

// ---------- 7. Display ----------
bool showLevels = input.bool(true, "Hiện Entry / Stop / TP", group = G_DISPLAY)
bool showLabels = input.bool(true, "Hiện nhãn giá & khối lượng", group = G_DISPLAY)
bool showZones = input.bool(true, "Tô vùng Risk / Reward", group = G_DISPLAY)
bool armExitAlerts = input.bool(false, "Arm alert Stop/TP (đã vào lệnh)", group = G_DISPLAY,
     tooltip = "Chỉ có hiệu lực với kế hoạch STATIC. Bật khi bạn đã vào lệnh; alert chỉ báo giá chạm mức, không quản lý vị thế broker.")
int barsBack = input.int(20, "Kéo đường về quá khứ (bar)", minval = 0, maxval = 500, group = G_DISPLAY)
int barsForward = input.int(30, "Kéo đường về tương lai (bar)", minval = 1, maxval = 200, group = G_DISPLAY)
string panelPositionInput = input.string("Trên phải", "Vị trí bảng", options = ["Trên phải", "Trên trái", "Dưới phải", "Dưới trái"], group = G_DISPLAY)
float highRiskWarningPct = input.float(2.0, "Cảnh báo khi risk vượt (%)", minval = 0.01, maxval = 100.0, step = 0.25, group = G_DISPLAY)

// ============================================================================
// Core calculations
// ============================================================================

bool isLong = side == "Long"
float direction = isLong ? 1.0 : -1.0
float atrValue = ta.atr(atrLength)

float entryRaw = entryMode == "Giá hiện tại" ? close : manualEntryInput
// Conservative price rounding: adverse for entry/stop, favorable-side targets
// rounded toward Entry. This prevents sub-tick prices from understating risk.
float entryPrice = isLong ? f_ceil_tick(entryRaw) : f_floor_tick(entryRaw)

float stopRaw = switch stopMode
    "Giá thủ công" => manualStopInput
    "% từ Entry" => entryPrice - direction * math.abs(entryPrice) * stopPercent / 100.0
    "ATR" => entryPrice - direction * atrValue * atrMultiple
    => entryPrice - direction * stopTicks * syminfo.mintick

float stopPrice = isLong ? f_floor_tick(stopRaw) : f_ceil_tick(stopRaw)
float priceDistance = math.abs(entryPrice - stopPrice)
float distanceTicks = syminfo.mintick > 0 ? priceDistance / syminfo.mintick : na
float distancePercent = entryPrice != 0 ? priceDistance / math.abs(entryPrice) * 100.0 : na

float tp1Raw = targetMode == "Theo R" ? entryPrice + direction * priceDistance * tp1R : manualTp1Input
float tp2Raw = targetMode == "Theo R" ? entryPrice + direction * priceDistance * tp2R : manualTp2Input
float tp3Raw = targetMode == "Theo R" ? entryPrice + direction * priceDistance * tp3R : manualTp3Input
float tp1Price = isLong ? f_floor_tick(tp1Raw) : f_ceil_tick(tp1Raw)
float tp2Price = isLong ? f_floor_tick(tp2Raw) : f_ceil_tick(tp2Raw)
float tp3Price = isLong ? f_floor_tick(tp3Raw) : f_ceil_tick(tp3Raw)

float tp3AllocationRaw = 100.0 - tp1AllocationPct - tp2AllocationPct
bool allocationOK = tp3AllocationRaw >= -1e-9
float tp3AllocationPct = allocationOK ? math.max(tp3AllocationRaw, 0.0) : tp3AllocationRaw
bool tp1Enabled = tp1AllocationPct > 0
bool tp2Enabled = tp2AllocationPct > 0
bool tp3Enabled = tp3AllocationPct > 0
bool stopGeometryOK = not na(entryPrice) and not na(stopPrice) and entryPrice != 0 and direction * (entryPrice - stopPrice) > 0
bool tp1SideOK = not tp1Enabled or direction * (tp1Price - entryPrice) > 0
bool tp2SideOK = not tp2Enabled or direction * (tp2Price - entryPrice) > 0
bool tp3SideOK = not tp3Enabled or direction * (tp3Price - entryPrice) > 0
bool tp12OrderOK = not (tp1Enabled and tp2Enabled) or direction * (tp2Price - tp1Price) >= 0
bool tp13OrderOK = not (tp1Enabled and tp3Enabled) or direction * (tp3Price - tp1Price) >= 0
bool tp23OrderOK = not (tp2Enabled and tp3Enabled) or direction * (tp3Price - tp2Price) >= 0
bool targetsGeometryOK = tp1SideOK and tp2SideOK and tp3SideOK and tp12OrderOK and tp13OrderOK and tp23OrderOK
bool chartOK = chart.is_standard or allowNonStandardChart

// Currency request is intentionally executed on every bar. Auto rate is a daily
// reference rate. If unavailable, the script never silently assumes 1.
float automaticFxRate = request.currency_rate(syminfo.currency, accountCurrency, ignore_invalid_currency = true)
bool quoteEqualsAccount = syminfo.currency == accountCurrency
float quoteToAccountFx = quoteEqualsAccount ? 1.0 : (fxMode == "Thủ công" ? manualFxRate : automaticFxRate)

bool autoLinear = pnlModel == "Auto Linear"
bool manualPoint = pnlModel == "Manual Value/Point"
bool manualTick = pnlModel == "Manual Tick Value"
bool directLoss = pnlModel == "Direct Loss/Qty"
bool directSnapshotOK = not directLoss or (entryMode == "Giá thủ công" and stopMode == "Giá thủ công")
bool tickValueInAccount = tickValueCurrency == "Account"
bool fxRequiredForPnl = autoLinear or manualPoint or (manualTick and not tickValueInAccount)
bool fxOK = not fxRequiredForPnl or (not na(quoteToAccountFx) and quoteToAccountFx > 0)

float autoPointValue = syminfo.pointvalue
float effectiveTicks = distanceTicks + adverseTicks
float priceLossPerQtyAccount = switch pnlModel
    "Auto Linear" => priceDistance * autoPointValue * quoteToAccountFx + adverseTicks * syminfo.mintick * autoPointValue * quoteToAccountFx
    "Manual Value/Point" => priceDistance * manualPointValue * quoteToAccountFx + adverseTicks * syminfo.mintick * manualPointValue * quoteToAccountFx
    "Manual Tick Value" => effectiveTicks * manualTickValue * (tickValueInAccount ? 1.0 : quoteToAccountFx)
    => directLossPerQty

bool modelSpecOK = switch pnlModel
    "Auto Linear" => not na(autoPointValue) and autoPointValue > 0
    "Manual Value/Point" => manualPointValue > 0
    "Manual Tick Value" => manualTickValue > 0 and syminfo.mintick > 0
    => directLossPerQty > 0

float notionalMultiplierAccount = switch pnlModel
    "Auto Linear" => autoPointValue * quoteToAccountFx
    "Manual Value/Point" => manualPointValue * quoteToAccountFx
    "Manual Tick Value" => manualTickValue / syminfo.mintick * (tickValueInAccount ? 1.0 : quoteToAccountFx)
    => na

float entryNotionalPerQty = directLoss ? (manualNotionalPerQty > 0 ? manualNotionalPerQty : na) : math.abs(entryPrice) * notionalMultiplierAccount
float stopNotionalPerQty = directLoss ? (manualNotionalPerQty > 0 ? manualNotionalPerQty : na) : math.abs(stopPrice) * notionalMultiplierAccount

bool pctFeeNeedsNotional = feePercentPerSide > 0
float percentFeeAtStopPerQty = pctFeeNeedsNotional ? feePercentPerSide / 100.0 * (entryNotionalPerQty + stopNotionalPerQty) : 0.0
float variableCostAtStopPerQty = cashFeePerQtyRT + percentFeeAtStopPerQty
float plannedLossPerQty = priceLossPerQtyAccount + variableCostAtStopPerQty
bool directFeeModelOK = not directLoss or not pctFeeNeedsNotional
bool directMarginModelOK = not directLoss or not useMarginCap or marginModel == "Margin / qty thủ công"
bool directBufferModelOK = not directLoss or adverseTicks == 0
bool directTargetModelOK = not directLoss or targetMode == "Giá thủ công"

float requestedRiskBudget = riskMode == "% vốn" ? accountEquity * riskPercent / 100.0 : fixedRiskCash
float portfolioRoom = math.max(accountEquity * portfolioRiskCapPct / 100.0 - currentOpenRiskCash, 0.0)
float usableRiskBudget = usePortfolioCap ? math.min(requestedRiskBudget, portfolioRoom) : requestedRiskBudget
float requestedRiskPctActual = accountEquity > 0 ? requestedRiskBudget / accountEquity * 100.0 : na

float autoQtyStep = syminfo.mincontract
float qtyStepUsed = useAutoQtyRules ? autoQtyStep : manualQtyStep
float minQtyUsed = useAutoQtyRules ? autoQtyStep : manualMinQty
bool qtyRulesOK = not na(qtyStepUsed) and qtyStepUsed > 0 and not na(minQtyUsed) and minQtyUsed > 0

bool notionalNeeded = minNotionalInput > 0 or (not directLoss and (pctFeeNeedsNotional or (useMarginCap and marginModel == "Notional / đòn bẩy")))
bool notionalOK = not notionalNeeded or (not na(entryNotionalPerQty) and entryNotionalPerQty > 0 and not na(stopNotionalPerQty))

float marginPerQty = marginModel == "Margin / qty thủ công" ? (manualMarginPerQty > 0 ? manualMarginPerQty : na) : (not na(entryNotionalPerQty) and leverage > 0 ? entryNotionalPerQty / leverage : na)
float entryFeeReservePerQty = cashFeePerQtyRT + (pctFeeNeedsNotional ? feePercentPerSide / 100.0 * entryNotionalPerQty : 0.0)
float marginFundingPerQty = not na(marginPerQty) ? marginPerQty + entryFeeReservePerQty : na
float marginBudgetAfterFixedReserve = math.max(availableMargin * maxMarginUsePct / 100.0 - fixedFeeRoundTrip, 0.0)
bool marginCapOK = not useMarginCap or (not na(marginFundingPerQty) and marginFundingPerQty > 0 and marginBudgetAfterFixedReserve > 0)

bool sizingInputsOK = accountEquity > 0 and chartOK and stopGeometryOK and fxOK and modelSpecOK and qtyRulesOK and notionalOK and marginCapOK and directFeeModelOK and directMarginModelOK and directBufferModelOK and directSnapshotOK and usableRiskBudget > fixedFeeRoundTrip and not na(plannedLossPerQty) and plannedLossPerQty > 0

float rawRiskQty = sizingInputsOK ? (usableRiskBudget - fixedFeeRoundTrip) / plannedLossPerQty : na
float riskLimitedQty = sizingInputsOK ? f_floor_step(rawRiskQty, qtyStepUsed) : na
float riskTolerance = math.max(usableRiskBudget, 1.0) * 1e-10
if sizingInputsOK and not na(riskLimitedQty) and fixedFeeRoundTrip + riskLimitedQty * plannedLossPerQty > usableRiskBudget + riskTolerance
    riskLimitedQty := math.max(riskLimitedQty - qtyStepUsed, 0.0)
float marginQty = useMarginCap and marginCapOK ? f_floor_step(marginBudgetAfterFixedReserve / marginFundingPerQty, qtyStepUsed) : na
float marginTolerance = math.max(marginBudgetAfterFixedReserve, 1.0) * 1e-10
if useMarginCap and marginCapOK and not na(marginQty) and marginQty * marginFundingPerQty > marginBudgetAfterFixedReserve + marginTolerance
    marginQty := math.max(marginQty - qtyStepUsed, 0.0)
float maxQtyRounded = maxQtyInput > 0 and qtyRulesOK ? f_floor_step(maxQtyInput, qtyStepUsed) : na

float candidateQty = riskLimitedQty
if sizingInputsOK and useMarginCap
    candidateQty := math.min(candidateQty, marginQty)
if sizingInputsOK and maxQtyInput > 0
    candidateQty := math.min(candidateQty, maxQtyRounded)
candidateQty := sizingInputsOK ? f_floor_step(candidateQty, qtyStepUsed) : na

bool quantityMeetsMinimum = not na(candidateQty) and candidateQty >= minQtyUsed and candidateQty > 0
float candidateNotional = not na(candidateQty) and not na(entryNotionalPerQty) ? candidateQty * entryNotionalPerQty : na
bool minNotionalOK = minNotionalInput <= 0 or (not na(candidateNotional) and candidateNotional >= minNotionalInput)
bool canSize = sizingInputsOK and quantityMeetsMinimum and minNotionalOK
float recommendedQty = canSize ? candidateQty : 0.0
float actualPlannedRisk = canSize ? fixedFeeRoundTrip + recommendedQty * plannedLossPerQty : 0.0
float actualRiskPct = accountEquity > 0 ? actualPlannedRisk / accountEquity * 100.0 : na
float totalNotional = canSize and not na(entryNotionalPerQty) ? recommendedQty * entryNotionalPerQty : na
float estimatedMargin = canSize and not na(marginPerQty) and marginPerQty > 0 ? recommendedQty * marginPerQty : na
float estimatedMarginWithReserve = canSize and not na(marginFundingPerQty) ? fixedFeeRoundTrip + recommendedQty * marginFundingPerQty : na
float lotEquivalent = canSize and qtyPerLot > 0 ? recommendedQty / qtyPerLot : na

bool marginBinding = canSize and useMarginCap and not na(marginQty) and marginQty + qtyStepUsed * 0.5 < riskLimitedQty and (maxQtyInput <= 0 or marginQty <= maxQtyRounded)
bool maxQtyBinding = canSize and maxQtyInput > 0 and not na(maxQtyRounded) and maxQtyRounded + qtyStepUsed * 0.5 < riskLimitedQty and (not useMarginCap or maxQtyRounded <= marginQty)

// Partial exits use the largest-remainder method on whole broker steps. This
// preserves the total entry qty and never sends rounding remainder to a 0% leg.
int totalQtySteps = canSize and qtyStepUsed > 0 ? int(math.round(recommendedQty / qtyStepUsed)) : 0
float idealTp1Steps = totalQtySteps * tp1AllocationPct / 100.0
float idealTp2Steps = totalQtySteps * tp2AllocationPct / 100.0
float idealTp3Steps = totalQtySteps * tp3AllocationPct / 100.0
int tp1StepCount = int(math.floor(idealTp1Steps))
int tp2StepCount = int(math.floor(idealTp2Steps))
int tp3StepCount = int(math.floor(idealTp3Steps))
int extraExitSteps = math.max(totalQtySteps - tp1StepCount - tp2StepCount - tp3StepCount, 0)
float tp1Remainder = tp1Enabled ? idealTp1Steps - tp1StepCount : -1.0
float tp2Remainder = tp2Enabled ? idealTp2Steps - tp2StepCount : -1.0
float tp3Remainder = tp3Enabled ? idealTp3Steps - tp3StepCount : -1.0

if extraExitSteps > 0
    if tp1Remainder >= tp2Remainder and tp1Remainder >= tp3Remainder
        tp1StepCount += 1
        tp1Remainder := -1.0
    else if tp2Remainder >= tp3Remainder
        tp2StepCount += 1
        tp2Remainder := -1.0
    else
        tp3StepCount += 1
        tp3Remainder := -1.0
if extraExitSteps > 1
    if tp1Remainder >= tp2Remainder and tp1Remainder >= tp3Remainder
        tp1StepCount += 1
        tp1Remainder := -1.0
    else if tp2Remainder >= tp3Remainder
        tp2StepCount += 1
        tp2Remainder := -1.0
    else
        tp3StepCount += 1
        tp3Remainder := -1.0
if extraExitSteps > 2
    if tp1Remainder >= tp2Remainder and tp1Remainder >= tp3Remainder
        tp1StepCount += 1
    else if tp2Remainder >= tp3Remainder
        tp2StepCount += 1
    else
        tp3StepCount += 1

float tp1Qty = canSize and allocationOK ? tp1StepCount * qtyStepUsed : 0.0
float tp2Qty = canSize and allocationOK ? tp2StepCount * qtyStepUsed : 0.0
float tp3Qty = canSize and allocationOK ? tp3StepCount * qtyStepUsed : 0.0
float tp1ActualPct = canSize and recommendedQty > 0 ? tp1Qty / recommendedQty * 100.0 : na
float tp2ActualPct = canSize and recommendedQty > 0 ? tp2Qty / recommendedQty * 100.0 : na
float tp3ActualPct = canSize and recommendedQty > 0 ? tp3Qty / recommendedQty * 100.0 : na
bool tp1LegOK = not tp1Enabled or tp1Qty >= minQtyUsed
bool tp2LegOK = not tp2Enabled or tp2Qty >= minQtyUsed
bool tp3LegOK = not tp3Enabled or tp3Qty >= minQtyUsed
float exitQtySum = tp1Qty + tp2Qty + tp3Qty
float exitQtyTolerance = qtyStepUsed * 0.25
bool exitsSumOK = not canSize or math.abs(exitQtySum - recommendedQty) <= exitQtyTolerance
bool exitsExecutable = not canSize or (tp1LegOK and tp2LegOK and tp3LegOK and exitsSumOK)

// Net reward is available for the three linear models. Direct Loss/Qty deliberately
// returns N/A because a nonlinear instrument's target P&L cannot be inferred safely.
float adversePriceDistance = adverseTicks * syminfo.mintick
float tp1NetDistance = direction * (tp1Price - entryPrice) - adversePriceDistance
float tp2NetDistance = direction * (tp2Price - entryPrice) - adversePriceDistance
float tp3NetDistance = direction * (tp3Price - entryPrice) - adversePriceDistance

float tp1NotionalPerQty = directLoss ? na : math.abs(tp1Price) * notionalMultiplierAccount
float tp2NotionalPerQty = directLoss ? na : math.abs(tp2Price) * notionalMultiplierAccount
float tp3NotionalPerQty = directLoss ? na : math.abs(tp3Price) * notionalMultiplierAccount

float tp1GrossRewardPerQty = switch pnlModel
    "Auto Linear" => tp1NetDistance * autoPointValue * quoteToAccountFx
    "Manual Value/Point" => tp1NetDistance * manualPointValue * quoteToAccountFx
    "Manual Tick Value" => tp1NetDistance / syminfo.mintick * manualTickValue * (tickValueInAccount ? 1.0 : quoteToAccountFx)
    => na
float tp2GrossRewardPerQty = switch pnlModel
    "Auto Linear" => tp2NetDistance * autoPointValue * quoteToAccountFx
    "Manual Value/Point" => tp2NetDistance * manualPointValue * quoteToAccountFx
    "Manual Tick Value" => tp2NetDistance / syminfo.mintick * manualTickValue * (tickValueInAccount ? 1.0 : quoteToAccountFx)
    => na
float tp3GrossRewardPerQty = switch pnlModel
    "Auto Linear" => tp3NetDistance * autoPointValue * quoteToAccountFx
    "Manual Value/Point" => tp3NetDistance * manualPointValue * quoteToAccountFx
    "Manual Tick Value" => tp3NetDistance / syminfo.mintick * manualTickValue * (tickValueInAccount ? 1.0 : quoteToAccountFx)
    => na

float tp1VariableFeePerQty = directLoss ? na : cashFeePerQtyRT + (pctFeeNeedsNotional ? feePercentPerSide / 100.0 * (entryNotionalPerQty + tp1NotionalPerQty) : 0.0)
float tp2VariableFeePerQty = directLoss ? na : cashFeePerQtyRT + (pctFeeNeedsNotional ? feePercentPerSide / 100.0 * (entryNotionalPerQty + tp2NotionalPerQty) : 0.0)
float tp3VariableFeePerQty = directLoss ? na : cashFeePerQtyRT + (pctFeeNeedsNotional ? feePercentPerSide / 100.0 * (entryNotionalPerQty + tp3NotionalPerQty) : 0.0)

float tp1NetRewardPerQty = directLoss ? na : tp1GrossRewardPerQty - tp1VariableFeePerQty
float tp2NetRewardPerQty = directLoss ? na : tp2GrossRewardPerQty - tp2VariableFeePerQty
float tp3NetRewardPerQty = directLoss ? na : tp3GrossRewardPerQty - tp3VariableFeePerQty
float expectedNetReward = canSize and allocationOK and targetsGeometryOK and exitsExecutable and not directLoss ? tp1Qty * tp1NetRewardPerQty + tp2Qty * tp2NetRewardPerQty + tp3Qty * tp3NetRewardPerQty - fixedFeeRoundTrip : na
float netRewardRiskRatio = not na(expectedNetReward) and actualPlannedRisk > 0 ? expectedNetReward / actualPlannedRisk : na
bool planReady = canSize and directTargetModelOK and allocationOK and targetsGeometryOK and exitsExecutable

// ---------- Display unit ----------
string qtyUnit = qtyUnitInput == "Native qty" ? "native qty" : str.lower(qtyUnitInput)
bool showLotRow = syminfo.type == "forex" and qtyUnitInput == "Units"
// With a manual Entry, percentage/tick Stops are deterministic too. Only a
// current-price Entry or ATR-derived Stop keeps the levels moving bar to bar.
bool staticPlan = entryMode == "Giá thủ công" and stopMode != "ATR"
bool roundedExitWarning = canSize and ((tp1AllocationPct > 0 and tp1Qty == 0) or (tp2AllocationPct > 0 and tp2Qty == 0) or (tp3AllocationPct > 0 and tp3Qty == 0))
bool autoSpecNeedsReview = autoLinear and (syminfo.type == "forex" or syminfo.type == "crypto" or syminfo.type == "spot" or syminfo.type == "swap" or syminfo.type == "futures" or syminfo.type == "commodity" or syminfo.type == "index" or syminfo.type == "cfd")

// ---------- Status and diagnostics ----------
string statusDetail = ""
if not chartOK
    statusDetail := "Dùng chart nến chuẩn hoặc bật override"
else if not stopGeometryOK
    statusDetail := isLong ? "Long cần Stop < Entry" : "Short cần Stop > Entry"
else if not fxOK
    statusDetail := "Không có tỷ giá; hãy nhập FX thủ công"
else if not modelSpecOK
    statusDetail := "Thông số mô hình P&L không hợp lệ"
else if not qtyRulesOK
    statusDetail := "Bước/min khối lượng không hợp lệ"
else if not directFeeModelOK
    statusDetail := "Direct mode: đổi phí % sang phí tiền/qty"
else if not directMarginModelOK
    statusDetail := "Direct mode: dùng margin/qty thủ công"
else if not directBufferModelOK
    statusDetail := "Direct mode: đặt tick bất lợi = 0; gộp buffer vào Loss/qty"
else if not directSnapshotOK
    statusDetail := "Direct mode cần Entry/Stop thủ công cố định"
else if not directTargetModelOK
    statusDetail := "Direct mode: dùng TP giá thủ công, không dùng bội số R"
else if not notionalOK
    statusDetail := "Cần Notional/qty cho phí hoặc margin"
else if not marginCapOK
    statusDetail := "Thông số margin cap không hợp lệ"
else if usableRiskBudget <= fixedFeeRoundTrip
    statusDetail := "Ngân sách rủi ro không đủ trả phí cố định"
else if not quantityMeetsMinimum
    statusDetail := "Qty tính được nhỏ hơn mức tối thiểu"
else if not minNotionalOK
    statusDetail := "Notional tính được dưới mức tối thiểu"
else if not allocationOK
    statusDetail := "TP1% + TP2% đang vượt 100%"
else if not targetsGeometryOK
    statusDetail := "Các TP phải đúng phía và đúng thứ tự"
else if not exitsExecutable
    statusDetail := "Một phần TP nhỏ hơn min qty; giảm số tranche"
else
    statusDetail := "Kế hoạch hợp lệ"

string warningText = ""
if not chart.is_standard
    warningText := f_append(warningText, "Chart phi tiêu chuẩn dùng giá tổng hợp")
if not staticPlan
    warningText := f_append(warningText, "Mức giá đang DYNAMIC theo thị trường")
if requestedRiskPctActual > highRiskWarningPct
    warningText := f_append(warningText, "Rủi ro yêu cầu cao hơn ngưỡng cảnh báo")
if autoSpecNeedsReview
    warningText := f_append(warningText, "Hãy kiểm tra point value với broker/sàn")
if cashFeePerQtyRT == 0 and feePercentPerSide == 0 and fixedFeeRoundTrip == 0
    if directLoss
        warningText := f_append(warningText, "Phí tiền mặt đang bằng 0; xác nhận Direct Loss đã gồm buffer")
    else if adverseTicks == 0
        warningText := f_append(warningText, "Phí và execution buffer đều đang bằng 0")
if fxMode == "Tự động (tỷ giá ngày)" and fxRequiredForPnl and syminfo.currency != accountCurrency
    warningText := f_append(warningText, "FX tự động là tỷ giá tham chiếu theo ngày")
if directLoss
    warningText := f_append(warningText, "Direct Loss phải khớp snapshot Entry/Stop và tự gồm execution buffer")
if usePortfolioCap and usableRiskBudget < requestedRiskBudget
    warningText := f_append(warningText, "Ngân sách bị giới hạn bởi risk danh mục")
if marginBinding
    warningText := f_append(warningText, "Qty bị giới hạn bởi margin khả dụng")
if maxQtyBinding
    warningText := f_append(warningText, "Qty bị giới hạn bởi mức tối đa")
if qtyUnitInput == "Native qty"
    warningText := f_append(warningText, "Hãy xác nhận đơn vị qty: units/lots/contracts")
if useAutoQtyRules
    warningText := f_append(warningText, "Bước/min qty đang lấy tự động từ feed; hãy đối chiếu broker")
if roundedExitWarning
    warningText := f_append(warningText, "Một phần TP làm tròn về 0 qty")
if not directLoss and ((tp1Enabled and tp1NetDistance <= 0) or (tp2Enabled and tp2NetDistance <= 0) or (tp3Enabled and tp3NetDistance <= 0))
    warningText := f_append(warningText, "Execution buffer lớn hơn khoảng lời của một TP")
if not na(expectedNetReward) and expectedNetReward <= 0
    warningText := f_append(warningText, "Reward ròng của kế hoạch đang không dương")
if not useMarginCap and not na(estimatedMargin) and estimatedMargin > accountEquity
    warningText := f_append(warningText, "Margin ước tính đang lớn hơn equity")
if not staticPlan
    warningText := f_append(warningText, "Alert chạm mức bị tắt cho plan DYNAMIC")
if warningText == ""
    warningText := "• Không có cảnh báo cấu hình"

bool zeroCostAssumption = cashFeePerQtyRT == 0 and feePercentPerSide == 0 and fixedFeeRoundTrip == 0 and adverseTicks == 0
bool leverageNeedsReview = not useMarginCap and not na(estimatedMargin) and estimatedMargin > accountEquity
bool targetBufferNeedsReview = not directLoss and ((tp1Enabled and tp1NetDistance <= 0) or (tp2Enabled and tp2NetDistance <= 0) or (tp3Enabled and tp3NetDistance <= 0))
bool rewardNeedsReview = not na(expectedNetReward) and expectedNetReward <= 0
bool needsConfirmation = planReady and (not staticPlan or not chart.is_standard or qtyUnitInput == "Native qty" or useAutoQtyRules or zeroCostAssumption or autoSpecNeedsReview or directLoss or roundedExitWarning or leverageNeedsReview or targetBufferNeedsReview or rewardNeedsReview or requestedRiskPctActual > highRiskWarningPct)
bool fullyReady = planReady and not needsConfirmation

// ============================================================================
// Chart levels and zones (objects are reused; no object leak per bar)
// ============================================================================
color C_ENTRY = color.rgb(41, 121, 255)
color C_STOP  = color.rgb(239, 83, 80)
color C_TP1   = color.rgb(38, 166, 154)
color C_TP2   = color.rgb(0, 188, 212)
color C_TP3   = color.rgb(0, 150, 136)

var line entryLine = line.new(na, na, na, na, xloc = xloc.bar_index, extend = extend.none, color = C_ENTRY, width = 2)
var line stopLine  = line.new(na, na, na, na, xloc = xloc.bar_index, extend = extend.none, color = C_STOP, width = 2)
var line tp1Line   = line.new(na, na, na, na, xloc = xloc.bar_index, extend = extend.none, color = C_TP1, style = line.style_dashed)
var line tp2Line   = line.new(na, na, na, na, xloc = xloc.bar_index, extend = extend.none, color = C_TP2, style = line.style_dashed)
var line tp3Line   = line.new(na, na, na, na, xloc = xloc.bar_index, extend = extend.none, color = C_TP3, style = line.style_dashed, width = 2)
var line rewardAnchorLine = line.new(na, na, na, na, xloc = xloc.bar_index, extend = extend.none, color = color.new(C_TP3, 100))
var linefill riskZone = linefill.new(entryLine, stopLine, color.new(C_STOP, 89))
var linefill rewardZone = linefill.new(entryLine, rewardAnchorLine, color.new(C_TP3, 92))

var label entryLabel = label.new(na, na, "", xloc = xloc.bar_index, yloc = yloc.price, style = label.style_label_left, color = C_ENTRY, textcolor = color.white, size = size.small)
var label stopLabel  = label.new(na, na, "", xloc = xloc.bar_index, yloc = yloc.price, style = label.style_label_left, color = C_STOP, textcolor = color.white, size = size.small)
var label tp1Label   = label.new(na, na, "", xloc = xloc.bar_index, yloc = yloc.price, style = label.style_label_left, color = C_TP1, textcolor = color.white, size = size.small)
var label tp2Label   = label.new(na, na, "", xloc = xloc.bar_index, yloc = yloc.price, style = label.style_label_left, color = C_TP2, textcolor = color.white, size = size.small)
var label tp3Label   = label.new(na, na, "", xloc = xloc.bar_index, yloc = yloc.price, style = label.style_label_left, color = C_TP3, textcolor = color.white, size = size.small)

if barstate.islast
    int leftX = math.max(bar_index - barsBack, 0)
    int rightX = bar_index + barsForward
    bool showCore = showLevels and stopGeometryOK
    bool showTargetsNow = showCore and planReady
    bool showTp1Now = showTargetsNow and tp1Qty > 0
    bool showTp2Now = showTargetsNow and tp2Qty > 0
    bool showTp3Now = showTargetsNow and tp3Qty > 0
    bool showAnyTarget = showTp1Now or showTp2Now or showTp3Now
    float rewardAnchorPrice = showTp3Now ? tp3Price : showTp2Now ? tp2Price : tp1Price

    if showCore
        f_set_line(entryLine, leftX, rightX, entryPrice, C_ENTRY)
        f_set_line(stopLine, leftX, rightX, stopPrice, C_STOP)
    else
        f_hide_line(entryLine)
        f_hide_line(stopLine)

    if showTp1Now
        f_set_line(tp1Line, leftX, rightX, tp1Price, C_TP1)
    else
        f_hide_line(tp1Line)
    if showTp2Now
        f_set_line(tp2Line, leftX, rightX, tp2Price, C_TP2)
    else
        f_hide_line(tp2Line)
    if showTp3Now
        f_set_line(tp3Line, leftX, rightX, tp3Price, C_TP3)
    else
        f_hide_line(tp3Line)
    if showAnyTarget
        f_set_line(rewardAnchorLine, leftX, rightX, rewardAnchorPrice, color.new(C_TP3, 100))
    else
        f_hide_line(rewardAnchorLine)

    linefill.set_color(riskZone, showZones and showCore ? color.new(C_STOP, 89) : color.new(C_STOP, 100))
    linefill.set_color(rewardZone, showZones and showAnyTarget ? color.new(C_TP3, 92) : color.new(C_TP3, 100))

    if showLabels and showCore
        string entryTxt = "ENTRY  " + f_price(entryPrice) + (planReady ? "\nQty  " + f_qty(recommendedQty) + " " + qtyUnit : "")
        string stopTxt = "STOP  " + f_price(stopPrice) + (planReady ? "\nRisk  " + f_money(actualPlannedRisk) + " " + accountCurrency : "")
        f_set_label(entryLabel, rightX, entryPrice, entryTxt, C_ENTRY)
        f_set_label(stopLabel, rightX, stopPrice, stopTxt, C_STOP)
    else
        f_hide_label(entryLabel)
        f_hide_label(stopLabel)

    if showLabels and showTp1Now
        f_set_label(tp1Label, rightX, tp1Price, "TP1  " + f_price(tp1Price) + "\nExit  " + f_qty(tp1Qty), C_TP1)
    else
        f_hide_label(tp1Label)
    if showLabels and showTp2Now
        f_set_label(tp2Label, rightX, tp2Price, "TP2  " + f_price(tp2Price) + "\nExit  " + f_qty(tp2Qty), C_TP2)
    else
        f_hide_label(tp2Label)
    if showLabels and showTp3Now
        f_set_label(tp3Label, rightX, tp3Price, "TP3  " + f_price(tp3Price) + "\nExit  " + f_qty(tp3Qty), C_TP3)
    else
        f_hide_label(tp3Label)

// ============================================================================
// Dashboard
// ============================================================================
string panelPosition = panelPositionInput == "Trên trái" ? position.top_left : panelPositionInput == "Dưới phải" ? position.bottom_right : panelPositionInput == "Dưới trái" ? position.bottom_left : position.top_right
var table dashboard = table.new(panelPosition, 2, 22, frame_color = color.rgb(55, 65, 81), frame_width = 1, border_color = color.rgb(44, 52, 68), border_width = 1)

if barstate.islast
    color headerBg = color.rgb(17, 24, 39)
    color rowBg = color.new(color.rgb(24, 32, 48), 5)
    color altBg = color.new(color.rgb(31, 41, 55), 5)
    color goodColor = color.rgb(52, 211, 153)
    color badColor = color.rgb(248, 113, 113)
    color warnColor = color.rgb(251, 191, 36)
    color statusColor = fullyReady ? goodColor : planReady ? warnColor : badColor
    string panelStatus = fullyReady ? "SẴN SÀNG" : planReady ? "CẦN XÁC NHẬN" : "KHÔNG HỢP LỆ"
    string dynamicBadge = staticPlan ? "STATIC" : "DYNAMIC"

    table.cell(dashboard, 0, 0, "RISK MANAGER PRO", text_color = color.white, bgcolor = headerBg, text_halign = text.align_left, text_size = size.normal)
    table.cell(dashboard, 1, 0, side + " · " + dynamicBadge, text_color = isLong ? goodColor : badColor, bgcolor = headerBg, text_halign = text.align_right, text_size = size.normal)
    f_row(dashboard, 1, "Trạng thái", panelStatus, statusColor, rowBg)
    f_row(dashboard, 2, "Mã / loại", syminfo.ticker + " · " + syminfo.type, color.white, altBg)
    f_row(dashboard, 3, "Tài khoản", f_money(accountEquity) + " " + accountCurrency, color.white, rowBg)
    f_row(dashboard, 4, "Risk yêu cầu", f_money(requestedRiskBudget) + " " + accountCurrency + " · " + f_pct(requestedRiskPctActual), warnColor, altBg)
    f_row(dashboard, 5, "Risk khả dụng", f_money(usableRiskBudget) + " " + accountCurrency, usePortfolioCap and usableRiskBudget < requestedRiskBudget ? warnColor : color.white, rowBg)
    f_row(dashboard, 6, "Entry / Stop", f_price(entryPrice) + " / " + f_price(stopPrice), color.white, altBg)
    f_row(dashboard, 7, "Khoảng Stop", f_price(priceDistance) + " · " + f_qty(distanceTicks) + " ticks · " + f_pct(distancePercent), color.white, rowBg)
    f_row(dashboard, 8, "Mô hình P&L", pnlModel, color.white, altBg)
    string contractSpecText = autoLinear ? "PV " + f_qty(autoPointValue) + " " + syminfo.currency + "/point [AUTO]" : manualPoint ? "PV " + f_qty(manualPointValue) + " " + syminfo.currency + "/point [MANUAL]" : manualTick ? "Tick value " + f_money(manualTickValue) + " " + tickValueCurrency + " [MANUAL]" : "Loss/qty nhập trực tiếp [MANUAL]"
    f_row(dashboard, 9, "Thông số hợp đồng", contractSpecText, autoLinear ? warnColor : color.white, rowBg)
    string qtyRulesText = "Step " + f_qty(qtyStepUsed) + " · Min " + f_qty(minQtyUsed) + (useAutoQtyRules ? " [AUTO]" : " [MANUAL]")
    f_row(dashboard, 10, "Bước / min qty", qtyRulesText, useAutoQtyRules ? warnColor : color.white, altBg)
    f_row(dashboard, 11, "Loss / qty", f_money(plannedLossPerQty) + " " + accountCurrency, color.white, rowBg)
    string fxText = fxRequiredForPnl ? syminfo.currency + "→" + accountCurrency + " = " + f_qty(quoteToAccountFx) + (quoteEqualsAccount ? " [SAME CCY]" : fxMode == "Thủ công" ? " [MANUAL]" : " [DAILY]") : "Không cần cho P&L"
    f_row(dashboard, 12, "Quy đổi FX", fxText, fxOK ? color.white : badColor, altBg)
    string qtyText = planReady ? f_qty(recommendedQty) + " " + qtyUnit + (showLotRow ? " · " + f_qty(lotEquivalent) + " lots" : "") : "NO TRADE"
    f_row(dashboard, 13, "Khối lượng", qtyText, planReady ? goodColor : badColor, rowBg)
    f_row(dashboard, 14, "Risk thực tính", f_money(actualPlannedRisk) + " " + accountCurrency + " · " + f_pct(actualRiskPct), planReady ? warnColor : badColor, altBg)
    f_row(dashboard, 15, "Notional", f_money(totalNotional) + (na(totalNotional) ? "" : " " + accountCurrency), color.white, rowBg)
    string marginText = na(estimatedMarginWithReserve) ? "N/A" : f_money(estimatedMarginWithReserve) + " " + accountCurrency + (marginModel == "Notional / đòn bẩy" ? " @ " + f_qty(leverage) + "x" : " [manual]")
    f_row(dashboard, 16, "Margin + dự phòng phí", marginText, marginBinding ? warnColor : color.white, altBg)
    string tp1Text = tp1Enabled ? f_price(tp1Price) + " / " + f_qty(tp1Qty) + " (" + f_pct(tp1AllocationPct) + "→" + f_pct(tp1ActualPct) + ")" : "TẮT"
    string tp2Text = tp2Enabled ? f_price(tp2Price) + " / " + f_qty(tp2Qty) + " (" + f_pct(tp2AllocationPct) + "→" + f_pct(tp2ActualPct) + ")" : "TẮT"
    string tp3Text = tp3Enabled ? f_price(tp3Price) + " / " + f_qty(tp3Qty) + " (" + f_pct(tp3AllocationPct) + "→" + f_pct(tp3ActualPct) + ")" : "TẮT"
    f_row(dashboard, 17, "TP1 / Exit", tp1Text, color.white, rowBg)
    f_row(dashboard, 18, "TP2 / Exit", tp2Text, color.white, altBg)
    f_row(dashboard, 19, "TP3 / Exit", tp3Text, color.white, rowBg)
    string rrText = directLoss ? "N/A cho mô hình phi tuyến" : f_qty(netRewardRiskRatio) + "R · Net " + f_money(expectedNetReward) + " " + accountCurrency
    f_row(dashboard, 20, "R:R ròng", rrText, not na(netRewardRiskRatio) and netRewardRiskRatio >= 1 ? goodColor : warnColor, altBg)
    f_row(dashboard, 21, "Kiểm tra", planReady ? warningText : "• " + statusDetail + "\n" + warningText, planReady ? warnColor : badColor, rowBg)

// ============================================================================
// Alert conditions
// Alerts are independent level-reach events only; they do not track broker state.
// Stop/TP alerts require a STATIC plan and the explicit Arm toggle.
// Recreate alerts after changing symbol, timeframe, Entry/Stop or script inputs.
// Use "Once Per Bar" when creating the alert. Directional barriers catch gaps.
// ============================================================================
bool entryReachedThisBar = (high >= entryPrice and low <= entryPrice) or (not na(close[1]) and math.min(low, close[1]) <= entryPrice and math.max(high, close[1]) >= entryPrice)
bool entryTouchNow = planReady and staticPlan and entryReachedThisBar
bool stopTouchNow = planReady and staticPlan and armExitAlerts and (isLong ? low <= stopPrice : high >= stopPrice)
bool tp1TouchNow = planReady and staticPlan and armExitAlerts and tp1Qty > 0 and (isLong ? high >= tp1Price : low <= tp1Price)
bool tp2TouchNow = planReady and staticPlan and armExitAlerts and tp2Qty > 0 and (isLong ? high >= tp2Price : low <= tp2Price)
bool tp3TouchNow = planReady and staticPlan and armExitAlerts and tp3Qty > 0 and (isLong ? high >= tp3Price : low <= tp3Price)

bool entryTouchEvent = entryTouchNow and not entryTouchNow[1]
bool stopTouchEvent = stopTouchNow and not stopTouchNow[1]
bool tp1TouchEvent = tp1TouchNow and not tp1TouchNow[1]
bool tp2TouchEvent = tp2TouchNow and not tp2TouchNow[1]
bool tp3TouchEvent = tp3TouchNow and not tp3TouchNow[1]

alertcondition(entryTouchEvent, "Giá chạm/vượt mức Entry", "Risk Manager Pro: {{ticker}} đã chạm hoặc gap qua mức Entry. Giá hiện tại: {{close}}.")
alertcondition(stopTouchEvent, "Giá chạm/vượt mức Stop", "Risk Manager Pro: {{ticker}} đã chạm hoặc gap qua mức Stop đã Arm. Giá hiện tại: {{close}}.")
alertcondition(tp1TouchEvent, "Giá chạm/vượt mức TP1", "Risk Manager Pro: {{ticker}} đã chạm hoặc gap qua mức TP1 đã Arm. Giá hiện tại: {{close}}.")
alertcondition(tp2TouchEvent, "Giá chạm/vượt mức TP2", "Risk Manager Pro: {{ticker}} đã chạm hoặc gap qua mức TP2 đã Arm. Giá hiện tại: {{close}}.")
alertcondition(tp3TouchEvent, "Giá chạm/vượt mức TP3", "Risk Manager Pro: {{ticker}} đã chạm hoặc gap qua mức TP3 đã Arm. Giá hiện tại: {{close}}.")
