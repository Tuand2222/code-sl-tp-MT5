//+------------------------------------------------------------------+
//|                                               TuanProtrade.mq5 |
//|          TuanProtrade - Capital & Risk Manager for MT5           |
//|     Hop nhat: EA PRO v8.5/v9.10 + TA 23415 + FTM 39150 + STTS    |
//|     v1.01: fix unmatched else in OCO Adopt workflow         |
//+------------------------------------------------------------------+
#property copyright "TuanProtrade - based on user-provided TradeDeskPro v12.1 source"
#property version   "1.01"
#property description "TuanProtrade: capital and risk manager, conservative OCO, persistent equity flatten, daily/weekly/monthly risk guard."
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

// ============================================================================
// KHAI BÁO NGUYÊN MẪU HÀM ĐIỀU PHỐI LIÊN MODULE (FORWARD DECLARATIONS)
// ============================================================================
void   ProcessCoreLogic();
void   RebuildCleanPanel(bool clearBeforeBuild);
void   UpdateHudAndTabValues(double dayPct, double weekPct, double monthPct,
                             int openCount, double totalOpenVol, double vwapEntry,
                             double repSL, double repTP, bool basketIsLong,
                             long anchorId, datetime earliestOpenTime,
                             double currentR, double netFloatingPnl);
void   PlaceManualOrder(bool isBuy);
void   PlaceOcoBracket();
void   CancelOcoPending(string groupFilter = "");
void   ProcessFailedOcoCleanup();
void   CancelTradeDeskPending();
void   CheckEquityProtect();
string EquityProtectKey(string suffix, bool accountWide);
void   CheckScheduledFlatten();
void   ProcessPendingOrderTrailing();
void   ProcessVirtualPending();
void   ArmOrCancelVirtualPending();
void   LoadVirtualPending();
void   ProcessVirtualTakeProfits();
void   ProcessVirtualStops();
bool   SaveVirtualStopForDeal(ulong dealTicket, double targetSL, double emergencySL);
void   SaveVirtualStopForLatestPosition(bool isBuy, double targetSL, double emergencySL);
void   SaveVirtualTPForDeal(ulong dealTicket, double targetTP);
void   SaveVirtualTPForLatestPosition(bool isBuy, double targetTP);
void   CheckSupportResistanceBreakout();
void   CheckExternalSignalBridge();
void   HandleTradeDeskHotkey(int keyCode, bool shiftDown);
void   QueueTradeDeskNotification(string message, bool telegramEvent = true, string photoFile = "");
void   ProcessTradeDeskNotificationQueue();
void   ClosePositionsByFilter(bool winnersOnly, bool losersOnly, int sideFilter, bool accountWide = false);
void   SwitchChartSymbol(int direction);
void   ProcessAdvancedTrailing();
void   ProcessWeeklySchedule();
bool   GetRiskCashBudgetForShare(double riskShare, double &budget, string &reason);
bool   GetPreviousPeriodBalance(ENUM_TIMEFRAMES period, double &balanceAtPeriodStart);
void   HandleExternalPositionEntry(ulong dealTicket);
double GetActiveRiskPercent();
double SelectedPositionStopForLogic();
void   SaveTradeDeskProfile();
void   LoadTradeDeskProfile();
string CaptureChartScreenshot(bool silentMode = false, string customTag = "");
void   ApplyStepBreakEven(long posId, bool isBuy, double entry, double oneR, double currentR, double currentProfitPts, double tpPrice, double &targetSL);
string AccountScopedGV(string key);
int    GetCurrentServerHash();
bool   PreparePositionPartialState(long positionId, string partialStateKey);
bool   TradeDeskEntryGate(string &reason);
bool   ModifyPositionWithConfirmation(ulong ticket, double sl, double tp);
bool   ClosePositionWithConfirmation(ulong ticket);
bool   ClosePositionPartiallyByTicket(ulong ticket, double requestedVolume, double &actualClosedVolume);
bool   ClosePositionPartiallyByTicket(ulong ticket, double requestedVolume);
bool   DeleteOrderWithConfirmation(ulong ticket);
void   CloseAllTradesAndOrders(string reason, bool accountWide = true);
// [PATCH v12.1] Nguyên mẫu bổ sung
int    CountPositionsInScope(bool accountWide);
bool   ValidateStopsForModify(ulong ticket, double &sl, double &tp, string &reason);
double ExecPoint();
bool   IsProtectedGVName(string name);
void   TouchCriticalGlobals();
void   TgEnqueueOnly(string message, string photoFile);
void   SendSttsSignalCard(bool isBuy);
void   CheckRiskQuotaWarnings(double dayPct, double weekPct, double monthPct,
                              double maxDay, double maxWeek, double maxMonth);
void   CheckAccountRiskWarnings();
void   WriteTradeJournalCsvRow(string eventType, ulong ticket, string sideStr, double volume,
                               double entryPrice, double slPrice, double tpPrice, double closePrice,
                               double pointsRes, double netProfitCash, string noteStr);

// ============================================================================
// ĐỊNH NGHĨA TOÀN BỘ KIỂU LIỆT KÊ (ENUMERATIONS CHUẨN HÓA V12)
// ============================================================================
enum ENUM_UI_TAB
{
   TAB_POSITION = 0, // Tab 1: TRADE (Lập kế hoạch, Sizer, Chia lệnh, Lệnh chờ)
   TAB_TRAILING = 1, // Tab 2: MANAGE (Vị thế, Partial 10 cấp, BE 4 cấp, 9 Trailing)
   TAB_RISKNEWS = 2, // Tab 3: GUARD (Risk Guard 3 chu kỳ, PIN, Equity Protect, Tin tức)
   TAB_AUTOMATE = 3, // Tab 4: AUTOMATE (Lệnh ảo, Mobile Sync 2 chiều, OCO, Lịch tuần)
   TAB_SETTINGS = 4  // Tab 5: SETTINGS (Giao diện, Phím tắt, Telegram Photo, STTS Bridge)
};

enum ENUM_DRAWER_MODE
{
   DRAWER_CLOSED          = 0, // Đóng ngăn kéo phụ
   DRAWER_PARTIAL_MATRIX  = 1, // Ngăn kéo 1: Ma trận 10 Cấp Partial TP & 10 Cấp Partial SL
   DRAWER_BE_TRAIL_MATRIX = 2, // Ngăn kéo 2: Ma trận 4 Cấp Breakeven & 4 Cấp Multi-Trail
   DRAWER_POS_VIRTUAL_BOOK= 3, // Ngăn kéo 3: Danh sách Vị thế & Sổ 20 Lệnh Chờ Ảo / Lịch Tuần
   DRAWER_HOTKEY_STTS     = 4  // Ngăn kéo 4: Ma trận 23 Phím tắt & Cầu nối Chỉ báo STTS
};

enum ENUM_TRADE_SIDE
{
   SIDE_LONG  = 0, // Hướng Mua (BUY)
   SIDE_SHORT = 1  // Hướng Bán (SELL)
};

enum ENUM_ORDER_ENTRY_MODE
{
   ENTRY_MODE_MARKET     = 0, // Lệnh Thị trường (Market)
   ENTRY_MODE_LIMIT      = 1, // Lệnh Chờ Limit (Buy/Sell Limit)
   ENTRY_MODE_STOP       = 2, // Lệnh Chờ Stop (Buy/Sell Stop)
   ENTRY_MODE_LPO        = 3, // Lệnh Limit Pullback 2 Pha (InvestSoft LPO)
   ENTRY_MODE_STOP_LIMIT = 4, // Lệnh Nguyên bản MT5 Buy/Sell Stop Limit
   ENTRY_MODE_OCO        = 5  // Lệnh Cặp OCO Đa Chế độ
};

enum ENUM_SL_CALC_MODE
{
   SL_MODE_ATR_FIRST  = 0, // Khoảng SL từ nến ATR đầu tiên (ATR * FirstMul)
   SL_MODE_ATR_LINE   = 1, // Khoảng SL tính tới đường ATR Neo hiện tại
   SL_MODE_POINTS     = 2, // Khoảng SL cố định theo điểm (Points)
   SL_MODE_DRAG       = 3, // Khoảng SL kéo thả trực tiếp trên biểu đồ (Sizer)
   SL_MODE_FIXED_CASH = 4  // Khoảng SL giải ngược từ số tiền chịu lỗ cố định ($)
};

enum ENUM_VOL_SLTP_RULE
{
   RULE_KEEP_DIST_CALC_CASH = 0, // Giữ nguyên khoảng cách SL/TP -> tính lại số tiền rủi ro
   RULE_SCALE_DIST_BY_VOL   = 1  // Giữ nguyên ngân sách rủi ro -> co giãn khoảng cách SL theo Lot
};

enum ENUM_MULTI_ORDER_MODE
{
   MULTI_BASKET_VWAP = 0, // Gộp rổ lệnh theo giá trung bình gia quyền khối lượng (VWAP)
   MULTI_INDIVIDUAL  = 1  // Quản lý tách biệt từng vị thế (Ticket độc lập)
};

enum ENUM_TRAIL_STYLE
{
   TRAIL_STYLE_AUTO_ATR  = 0, // 1. AUTO TRAIL (Bật Trailing tự động khi đạt ngưỡng R)
   TRAIL_STYLE_BE_FLOAT  = 1, // 2. THỦ CÔNG (Chỉ dời BE / Chốt từng phần, không Trailing)
   TRAIL_STYLE_MANUAL_SL = 2  // 3. SL TAY 100% (EA tuyệt đối không tự dịch chuyển SL)
};

enum ENUM_ADV_TRAIL_MODE
{
   ADV_TRAIL_OFF          = 0, // Dùng ATR Neo chủ lực (Mặc định của EA PRO)
   ADV_TRAIL_MA           = 1, // Trailing theo Đường Trung bình Động (Moving Average)
   ADV_TRAIL_FRACTAL      = 2, // Trailing theo Đỉnh/Đáy Fractals
   ADV_TRAIL_PSAR         = 3, // Trailing theo Parabolic SAR
   ADV_TRAIL_PIPS_BASIC   = 4, // Trailing theo Pips/Points cơ bản (Distance + Step)
   ADV_TRAIL_MULTI_4STAGE = 5, // Trailing 4 cấp thu hẹp khoảng cách theo đà lãi (FTM)
   ADV_TRAIL_ATR_SIMPLE   = 6, // Trailing ATR đơn giản không cần ngày neo
   ADV_TRAIL_HIGH_LOW_BAR = 7, // Trailing theo Đỉnh/Đáy của K nến đã đóng gần nhất
   ADV_TRAIL_PARTIAL_STEP = 8  // Trailing bậc thang kết hợp cắt từng phần khối lượng
};

enum ENUM_ATR_CALC_SOURCE
{
   ATR_SRC_CLOSE_SWING = 0, // Tính theo Giá đóng cửa + giới hạn Swing Low/High
   ATR_SRC_HIGH_LOW    = 1  // Tính theo Đỉnh/Đáy nến (High/Low)
};

enum ENUM_SWEEP_PROTECTION
{
   SWEEP_3LAYER_20PCT_1R = 0, // Bảo vệ 3 tầng (T1 rút râu giữ, T2 cắt 50%, T3 biên 20% 1R)
   SWEEP_WAIT_CANDLE_CLOSE = 1, // Chống quét râu 2 tầng (Chỉ đóng khi nến ATR đóng vượt đường)
   SWEEP_HARD_SL_ON_LINE = 2  // Đặt SL cứng trực tiếp trên đường ATR (Buffer = 0)
};

enum ENUM_ATR_TF_MODE
{
   ATR_TF_AUTO_ENTRY = 0, // Tự động chọn khung thời gian khớp khoảng SL nhất
   ATR_TF_FIXED_H1   = 1, // Cố định khung H1
   ATR_TF_FIXED_M15  = 2, // Cố định khung M15
   ATR_TF_FIXED_M5   = 3, // Cố định khung M5
   ATR_TF_FIXED_H4   = 4, // Cố định khung H4
   ATR_TF_FIXED_D1   = 5, // Cố định khung D1
   ATR_TF_CHART_CUR  = 6  // Theo khung thời gian hiện tại của biểu đồ
};

enum ENUM_NEWS_TIME_ZONE
{
   TZ_LOCAL_PC   = 0, // Giờ máy tính cục bộ (Local PC / VPS)
   TZ_MT5_SERVER = 1  // Giờ máy chủ sàn giao dịch (MT5 Trade Server)
};

enum ENUM_ACTION_SCOPE
{
   SCOPE_ACCOUNT      = 0, // Phạm vi toàn bộ tài khoản (Mọi Symbol)
   SCOPE_CHART_SYMBOL = 1  // Chỉ áp dụng cho Symbol trên biểu đồ hiện tại
};

enum ENUM_RISK_INPUT_MODE
{
   RISK_INPUT_CASH                 = 0, // 1. Số tiền cố định ($ Cash)
   RISK_INPUT_BALANCE_PCT          = 1, // 2. % Account Balance hiện tại
   RISK_INPUT_EQUITY_PCT           = 2, // 3. % Account Equity hiệu dụng
   RISK_INPUT_FREEMARGIN_PCT       = 3, // 4. % Free Margin hiện tại
   RISK_INPUT_CUSTOM_PCT           = 4, // 5. % Vốn tùy chỉnh (Custom Base)
   RISK_INPUT_PREVDAY_BALANCE_PCT  = 5, // 6. % Balance cuối ngày hôm qua
   RISK_INPUT_PREVWEEK_BALANCE_PCT = 6, // 7. % Balance cuối tuần trước
   RISK_INPUT_PREVMONTH_BALANCE_PCT= 7  // 8. % Balance cuối tháng trước
};

enum ENUM_TRIGGER_UNIT
{
   UNIT_RR          = 0, // Kích hoạt theo hệ số R:R (Multiple of 1R)
   UNIT_PIPS_POINTS = 1, // Kích hoạt theo số Điểm (Points)
   UNIT_PCT_OF_TP   = 2, // Kích hoạt theo % quãng đường từ Entry tới TP tổng
   UNIT_PRICE       = 3  // Kích hoạt theo mức giá tuyệt đối trên biểu đồ
};

enum ENUM_PARTIAL_VOL_MODE
{
   VOL_PCT_INITIAL   = 0, // Tính % trên khối lượng gốc ban đầu của vị thế
   VOL_PCT_REMAINING = 1  // Tính % trên khối lượng hiện còn lại của vị thế
};

enum ENUM_PARTIAL_SL_MODE
{
   PARTIAL_SL_CONSERVATIVE    = 0, // Giữ nguyên Lot gốc chuẩn 1R -> giảm tổng lỗ thực tế < 1R
   PARTIAL_SL_WEIGHTED_BUDGET = 1  // Quy đổi khoảng SL gia quyền để tổng lỗ qua 10 tầng đúng = 1R
};

enum ENUM_VSL_SIZING_BASIS
{
   VSL_SIZE_BY_VIRTUAL_STOP   = 0, // Định cỡ Lot chuẩn 1R theo khoảng cách SL Ảo (Chuẩn TA/FTM)
   VSL_SIZE_BY_EMERGENCY_STOP = 1  // Định cỡ Lot chuẩn 1R theo SL Khẩn cấp trên Broker (An toàn Quỹ)
};

enum ENUM_OCO_MODE
{
   OCO_BREAKOUT_STOP_STOP   = 0, // Buy Stop + Sell Stop (Đánh bứt phá hai đầu)
   OCO_REVERSAL_LIMIT_LIMIT = 1, // Buy Limit + Sell Limit (Đánh đảo chiều vùng biên)
   OCO_DIRECTIONAL_BUY      = 2, // Buy Limit + Buy Stop (Cùng hướng Mua: Đón hồi hoặc Phá cản)
   OCO_DIRECTIONAL_SELL     = 3, // Sell Limit + Sell Stop (Cùng hướng Bán: Đón hồi hoặc Phá cản)
   OCO_CUSTOM_ADOPT         = 4  // Gom tất cả lệnh chờ hiện có trên Symbol vào 1 nhóm OCO
};

enum ENUM_EXT_MAGIC_FILTER
{
   EXT_FILTER_ALL_EXTERNAL     = 0, // Quản lý mọi lệnh có Magic khác với Magic của EA này
   EXT_FILTER_MANUAL_MOBILE_0  = 1, // Chỉ quản lý lệnh tay trên Mobile/PC (Magic == 0)
   EXT_FILTER_CUSTOM_MAGIC     = 2  // Chỉ quản lý lệnh khớp với mã Magic chỉ định
};

enum ENUM_EQ_PROTECT_UNIT
{
   EQ_UNIT_CASH        = 0, // Tính theo số tiền nổi ($ Floating/Session Cash)
   EQ_UNIT_BALANCE_PCT = 1, // Tính theo % so với Account Balance
   EQ_UNIT_EQUITY_PEAK = 2  // Tính theo % sụt giảm/tăng trưởng so với đỉnh Equity
};

enum ENUM_EQ_POST_ACTION
{
   EQ_ACTION_CLOSE_ONLY          = 0, // Chỉ đóng hết vị thế & hủy lệnh chờ, không khóa
   EQ_ACTION_LOCK_UNTIL_NEXT_DAY = 1, // Đóng hết và khóa giao dịch cho tới 00:00 ngày mới
   EQ_ACTION_HARD_LOCK           = 2  // Đóng hết và khóa cứng cho tới khi mở khóa tay/PIN
};

enum ENUM_WEEKLY_ACTION
{
   WEEKLY_OPEN_BUY       = 0, // Mở lệnh Buy Market theo rủi ro cấu hình
   WEEKLY_OPEN_SELL      = 1, // Mở lệnh Sell Market theo rủi ro cấu hình
   WEEKLY_CLOSE_SYMBOL   = 2, // Đóng toàn bộ vị thế trên Symbol hiện tại
   WEEKLY_CLOSE_BUY      = 3, // Đóng toàn bộ vị thế Buy trên Symbol hiện tại
   WEEKLY_CLOSE_SELL     = 4, // Đóng toàn bộ vị thế Sell trên Symbol hiện tại
   WEEKLY_DELETE_PENDING = 5  // Xóa toàn bộ lệnh chờ của EA trên Symbol hiện tại
};

enum ENUM_COLOR_THEME
{
   THEME_COLORBLIND_SAFE = 0, // Bảng màu thân thiện người mù màu (Buy Xanh dương / Sell Cam)
   THEME_CLASSIC_GREENRED= 1  // Bảng màu kinh điển (Buy Xanh lá / Sell Đỏ)
};

enum ENUM_STTS_BRIDGE_MODE
{
   STTS_BRIDGE_OFF         = 0, // Tắt cầu nối chỉ báo ngoài (Thuần quản lý giao dịch)
   STTS_BRIDGE_FILTER_HUD  = 1, // Copilot Mode: Hiển thị xu hướng lên HUD & cảnh báo ngược chiều
   STTS_BRIDGE_AUTO_SIGNAL = 2  // Universal Mode: Gửi thẻ tín hiệu Telegram (+ tự vào lệnh nếu bật InpSttsAutoExecute)
};

// ============================================================================
// CẤU HÌNH THAM SỐ ĐẦU VÀO (9 NHÓM INPUTS TƯƠNG THÍCH NGƯỢC & MỞ RỘNG V12)
// ============================================================================
input group "=== 0. TỰ ĐỘNG CẬP NHẬT NGÀY NEO, KHUNG ATR & QUẢN LÝ 3 TẦNG ==="
input ENUM_ATR_TF_MODE      InpAtrTfMode                      = ATR_TF_AUTO_ENTRY;        // Chế độ chọn khung thời gian ATR
input bool                  InpAutoSyncAnchorDate             = true;                     // Tự động đồng bộ ngày neo theo lệnh/nến mới
input int                   InpStandbyLookbackBars            = 35;                       // Số nến lùi mặc định khi chờ lệnh (Standby)
input ENUM_TRADE_SIDE       InpTradeSide                      = SIDE_LONG;                // Hướng giao dịch dự kiến mặc định
input int                   InpEntryDateYear                  = 2026;                     // Năm neo ATR (Entry Year)
input int                   InpEntryDateMonth                 = 10;                       // Tháng neo ATR (Entry Month)
input int                   InpEntryDateDay                   = 15;                       // Ngày neo ATR (Entry Day)
input double                InpCustomEntryPrice               = 0.0;                      // Giá vào lệnh tùy chỉnh (0 = dùng giá Close)
input int                   InpAtrLength                      = 14;                       // Chu kỳ ATR (Pine Script ta.atr RMA)
input double                InpAtrMultiplier                  = 2.8;                      // Hệ số nhân ATR khi bám (Trailing Multiplier)
input double                InpCustomValueForFirstDay         = 2.0;                      // Hệ số nhân ATR cho nến đầu tiên (1R ban đầu)
input ENUM_ATR_CALC_SOURCE  InpAtrCalcSource                  = ATR_SRC_CLOSE_SWING;      // Nguồn giá tính ATR Neo (Close+Swing / High-Low)
input ENUM_SWEEP_PROTECTION InpSweepProtection                = SWEEP_3LAYER_20PCT_1R;    // Cơ chế chống quét râu (3 tầng / Đóng nến / SL cứng)
input double                InpTierBufferPctOf1R              = 20.0;                     // Độ rộng vùng đệm T1->T3 (% của 1R, mặc định 20%)
input int                   InpSwingLookbackBars              = 3;                        // Số nến dò đáy/đỉnh Swing gần nhất
input bool                  InpAutoRestartAtrOnBreak          = true;                     // Tự khởi động lại chu kỳ đường ATR sau khi gãy T3
input bool                  InpEnableAtrBarCache              = true;                     // [V12] Bật bộ nhớ đệm theo nến giảm tải CPU (< 1ms)

input group "=== 1. QUẢN LÝ VỊ THẾ, ĐỊNH CỠ 8 CƠ SỞ RISK, CHIA 3 NHỊP & SL/TP ==="
input ENUM_RISK_INPUT_MODE  InpRiskInputMode                  = RISK_INPUT_EQUITY_PCT;    // Cơ sở tính ngân sách rủi ro (8 chế độ TA)
input double                InpRiskPerTradePct                = 0.5;                      // Tổng ngân sách rủi ro cho Setup (% Vốn)
input double                InpRiskFixedCash                  = 100.0;                    // Ngân sách rủi ro cố định bằng tiền ($ khi chọn Cash)
input double                InpRiskCustomBase                 = 10000.0;                  // Mức vốn cơ sở tùy chỉnh ($ khi chọn % Custom)
input double                InpFixedCashSlBudget              = 100.0;                    // [V12] Số tiền chịu lỗ cố định để giải ngược SL ($)
input double                InpTargetRR                       = 2.0;                      // Tỷ lệ Lợi nhuận / Rủi ro mục tiêu (R:R)
input double                InpMaxPortfolioRiskPct            = 2.0;                      // Trần rủi ro toàn danh mục mở (%, 0 = Tắt)
input double                InpEnteredManualLot               = 0.0;                      // Khối lượng nhập tay dự kiến (0 = dùng Lot gợi ý)
input bool                  InpLockStandbySetupTfAndBar       = true;                     // Khóa cố định khung & nến cho Setup lúc chờ lệnh
input bool                  InpSplitSetupRiskAcrossOrders     = true;                     // Chia tổng rủi ro Setup qua 3 nhịp lệnh (50/30/20)
input double                InpLeg1RiskSharePct               = 50.0;                     // Tỷ trọng rủi ro Nhịp 1 (%)
input double                InpLeg2RiskSharePct               = 30.0;                     // Tỷ trọng rủi ro Nhịp 2 (%)
input double                InpLeg3RiskSharePct               = 20.0;                     // Tỷ trọng rủi ro Nhịp 3 (%)
input bool                  InpRecalcSlTpOnFillDeviation      = true;                     // Tự tính lại SL/TP & 1R theo Giá khớp thực tế
input double                InpMaxRiskOverrunWarnPct          = 5.0;                      // Cảnh báo khi trượt giá làm vượt ngân sách rủi ro (%)
input double                InpRejectMaxSlippagePctOf1R       = 0.0;                      // Đóng lệnh ngay nếu trượt giá xấu vượt quá % của 1R
input ENUM_SL_CALC_MODE     InpSlCalcMode                     = SL_MODE_ATR_FIRST;        // Nguồn tính khoảng cách Stop Loss
input ENUM_VOL_SLTP_RULE    InpVolSlTpRule                    = RULE_KEEP_DIST_CALC_CASH; // Quy tắc ứng xử SL/TP khi thay đổi khối lượng
input ENUM_MULTI_ORDER_MODE InpMultiOrderMode                 = MULTI_BASKET_VWAP;        // Chế độ quản lý nhiều lệnh (Gộp VWAP / Từng lệnh)
input bool                  InpAutoAttachSlTp                 = true;                     // Tự động gắn SL/TP khởi tạo cho lệnh mới
input int                   InpManualSlPoints                 = 350;                      // Khoảng cách SL nhập tay (Points)
input int                   InpBufferPoints                   = 10;                       // Điểm đệm cộng thêm vào SL khi tính rủi ro (Points)
input double                InpCommissionPerLot               = 0.0;                      // Phí hoa hồng 2 chiều ước tính trên 1.00 Lot ($)
input string                InpExecutionUnderlyingSymbol      = "";                       // [V12] Mã khớp lệnh gốc nếu chạy trên chart Renko/Giây

input group "=== 2. MA TRẬN 10 CẤP PARTIAL TP/SL, BREAKEVEN 4 CẤP & COMMON BE ==="
input ENUM_TRAIL_STYLE      InpTrailStyle                     = TRAIL_STYLE_AUTO_ATR;     // Chế độ vận hành SL chính (Auto Trail / Chờ BE / SL Tay)
input double                InpTrailingStartRR                = 2.0;                      // Mốc R bắt đầu kích hoạt ATR Trailing
input bool                  InpEnablePartialTP                = true;                     // Bật hệ thống Chốt lời từng phần (Partial TP)
input double                InpPartialAtRR                    = 2.0;                      // Mốc kích hoạt TP tầng 1 mặc định (R)
input double                InpPartialClosePct                = 50.0;                     // Tỷ lệ % khối lượng đóng tại TP tầng 1 (%)
input ENUM_PARTIAL_VOL_MODE InpPartialTpVolMode               = VOL_PCT_INITIAL;          // [V12] Cơ sở tính % khối lượng cắt TP (Lot gốc / Lot còn lại)
input string                InpPartialTpMatrixPreset          = "1,0,2.0,50;0,0,3.0,25;0,0,4.0,25"; // [V12] Chuỗi 10 tầng TP (On,Unit,Trig,Pct;...)
input bool                  InpPreventHardTpConflictWithPartial = true;                   // Gỡ Hard TP trên server khi xung đột với cắt từng phần
input bool                  InpEnablePartialSL                = false;                    // [V12] Bật hệ thống Cắt lỗ từng phần 10 cấp (Partial SL)
input ENUM_PARTIAL_SL_MODE  InpPartialSlMode                  = PARTIAL_SL_CONSERVATIVE;  // [V12] Chế độ định cỡ khi bật Partial SL
input string                InpPartialSlMatrixPreset          = "0,0,0.25,20;0,0,0.50,30;0,0,0.75,25"; // [V12] Chuỗi 10 tầng SL (On,Unit,Trig,Pct;...)
input bool                  InpEnableBe                       = false;                    // Bật dời SL về Hòa vốn cơ bản (1 cấp)
input double                InpBeTriggerRR                    = 2.0;                      // Mốc R kích hoạt Breakeven cơ bản
input int                   InpBePlusPoints                   = 10;                       // Điểm lãi cộng thêm khi dời Breakeven (Points)
input bool                  InpEnableCommonBe                 = true;                     // [V12] Bật tính & vẽ đường Common BE (VWAP + Phí + Swap)
input bool                  InpEnableLockProfit               = false;                    // Bật Khóa lợi nhuận (Lock Profit)
input double                InpLockTriggerRR                  = 2.0;                      // Mốc R kích hoạt Lock Profit
input double                InpLockLevelRR                    = 0.20;                     // Mức R lợi nhuận khóa tối thiểu
input bool                  InpEnableStepBreakEven            = false;                    // Bật Breakeven nhiều cấp (Tối đa 4 cấp)
input ENUM_TRIGGER_UNIT     InpStepBeTriggerUnit              = UNIT_RR;                  // [V12] Đơn vị kích hoạt cho 4 cấp Breakeven
input ENUM_TRIGGER_UNIT     InpStepBeLockUnit                 = UNIT_RR;                  // [V12] Đơn vị mức khóa cho 4 cấp Breakeven
input double                InpStepBE1TriggerR                = 1.0;                      // Cấp BE 1: Ngưỡng kích hoạt
input double                InpStepBE1LockR                   = 0.0;                      // Cấp BE 1: Mức khóa bảo vệ
input double                InpStepBE2TriggerR                = 1.5;                      // Cấp BE 2: Ngưỡng kích hoạt
input double                InpStepBE2LockR                   = 0.5;                      // Cấp BE 2: Mức khóa bảo vệ
input double                InpStepBE3TriggerR                = 2.0;                      // Cấp BE 3: Ngưỡng kích hoạt
input double                InpStepBE3LockR                   = 1.0;                      // Cấp BE 3: Mức khóa bảo vệ
input double                InpStepBE4TriggerR                = 3.0;                      // Cấp BE 4: Ngưỡng kích hoạt
input double                InpStepBE4LockR                   = 2.0;                      // Cấp BE 4: Mức khóa bảo vệ

input group "=== 3. BỘ 9 PHƯƠNG PHÁP TRAILING STOP NÂNG CAO ==="
input ENUM_ADV_TRAIL_MODE   InpAdvancedTrailMode              = ADV_TRAIL_OFF;            // Phương pháp Trailing mở rộng (OFF = dùng ATR Neo)
input ENUM_TIMEFRAMES       InpAdvancedTrailTimeframe         = PERIOD_CURRENT;           // Khung thời gian tính chỉ báo Trailing mở rộng
input double                InpAdvancedTrailStartR            = 1.0;                      // Mốc R bắt đầu kích hoạt Trailing mở rộng
input int                   InpAdvancedTrailBufferPoints      = 5;                        // Khoảng đệm điểm cộng thêm cho Trailing chỉ báo
input int                   InpTrailPipsDist                  = 200;                      // [V12] Khoảng cách bám cho Trailing Pips cơ bản (Points)
input int                   InpTrailPipsStep                  = 20;                       // [V12] Bước nhảy tối thiểu cho Trailing Pips (Points)
input string                InpMultiTrailPreset4              = "200,150,20;400,100,15;600,70,10;1000,40,5"; // [V12] 4 cấp Multi-Trail (GainPts,DistPts,StepPts;...)
input int                   InpTrailMAPeriod                  = 14;                       // Chu kỳ đường MA Trailing
input ENUM_MA_METHOD        InpTrailMAMethod                  = MODE_EMA;                 // Phương pháp tính đường MA Trailing
input ENUM_APPLIED_PRICE    InpTrailMAAppliedPrice            = PRICE_CLOSE;              // Nguồn giá áp dụng cho MA Trailing
input int                   InpTrailFractalLookback           = 100;                      // Số nến dò tìm đỉnh/đáy Fractal tối đa
input double                InpTrailSarStep                   = 0.02;                     // Bước tăng Parabolic SAR (Step)
input double                InpTrailSarMaximum                = 0.20;                     // Cực đại Parabolic SAR (Maximum)
input double                InpSimpleAtrMult                  = 2.5;                      // [V12] Hệ số nhân cho Trailing ATR đơn giản
input int                   InpHighLowBarCount                = 3;                        // [V12] Số nến đã đóng tìm đỉnh/đáy cho High-Low Bar Trail
input int                   InpPartialTrailStepPts            = 150;                      // [V12] Bước lãi kích hoạt Partial-Close Trail (Points)
input double                InpPartialTrailClosePct           = 25.0;                     // [V12] % khối lượng cắt mỗi nấc Partial-Close Trail

input group "=== 4. LỆNH CHỜ NÂNG CAO: STOP-LIMIT, LPO 2 PHA, OCO 4 CHẾ ĐỘ & SPLIT ==="
input long                  InpTradeMagicNumber               = 85001501;                 // Mã định danh Magic Number của TradeDesk Pro
input int                   InpMaxDeviationPoints             = 20;                       // Độ trượt giá tối đa cho phép khi gửi lệnh (Points)
input int                   InpStopLimitOffsetPoints          = 40;                       // [V12] Khoảng lệch giữa giá Stop và giá Limit (Stop-Limit)
input int                   InpPullbackDistancePoints         = 50;                       // Khoảng cách bám sóng hồi cho lệnh LPO (Points)
input bool                  InpLpoRequireVirtual              = true;                     // [V12] Vận hành LPO theo máy trạng thái 2 pha chuẩn FTM
input ENUM_OCO_MODE         InpOcoDefaultMode                 = OCO_BREAKOUT_STOP_STOP;   // [V12] Chế độ OCO mặc định (4 chế độ)
input double                InpOcoDistanceAtr                 = 0.50;                     // Khoảng cách đặt cặp OCO tự động (Hệ số nhân ATR)
input bool                  InpEnablePendingTrailing          = false;                    // Bật Trailing tự động cho lệnh chờ
input int                   InpPendingTrailDistPts            = 150;                      // [V12] Khoảng cách bám giá của lệnh chờ (Points, 0=theo ATR)
input int                   InpPendingTrailStepPts            = 15;                       // [V12] Bước dịch chuyển tối thiểu của lệnh chờ (Points)
input int                   InpPendingTrailMaxMoves           = 50;                       // [V12] Số lần dịch chuyển tối đa cho mỗi lệnh chờ (0=vô hạn)
input double                InpMaxLotPerOrder                 = 0.0;                      // Khối lượng tối đa mỗi lệnh con khi chia lệnh (0=Max sàn)
input int                   InpSplitOrderDelayMs              = 100;                      // Độ trễ giữa các lệnh con khi chia lệnh lớn (ms)
input int                   InpMaxSplitOrders                 = 20;                       // Số lượng lệnh con tối đa trong 1 lần chia

input group "=== 5. CHẾ ĐỘ ẨN (VIRTUAL SL/TP/PENDING) & ĐỒNG BỘ LỆNH MOBILE 2 CHIỀU ==="
input double                InpVirtualPendingExpiryHours      = 8.0;                      // Thời gian tự hủy lệnh chờ ảo nếu chưa khớp (Giờ)
input bool                  InpEnableVirtualTakeProfit        = false;                    // Bật Chốt lời ảo ẩn khỏi máy chủ (Virtual TP)
input bool                  InpEnableVirtualStopLoss          = false;                    // Bật Cắt lỗ ảo ẩn khỏi máy chủ (Virtual SL)
input bool                  InpEnableEmergencyServerSL        = true;                     // [V12] Luôn đặt SL bảo hiểm thảm họa trên máy chủ Broker
input double                InpEmergencySLMultiplier          = 1.50;                     // Hệ số khoảng cách SL khẩn cấp trên Broker (x lần SL ảo)
input ENUM_VSL_SIZING_BASIS InpVirtualSlSizingBasis           = VSL_SIZE_BY_EMERGENCY_STOP; // [V12] Cơ sở tính Lot khi bật SL ảo (Theo SL ảo / SL khẩn cấp)
input bool                  InpManageExternalTrades           = false;                    // Bật nhận diện & quản lý lệnh từ Mobile / EA khác
input ENUM_EXT_MAGIC_FILTER InpExternalMagicFilter            = EXT_FILTER_ALL_EXTERNAL;  // [V12] Bộ lọc Magic cho lệnh ngoài (Tất cả / Mobile=0 / Custom)
input long                  InpCustomExternalMagic            = 0;                        // [V12] Mã Magic ngoài cần quản lý (khi chọn Custom)
input bool                  InpAutoAttachExternalSlTp         = false;                    // [V12] Tự gắn SL/TP chuẩn cho lệnh Mobile chưa đặt SL/TP
input bool                  InpAutoReduceExternalOverRisk     = false;                    // Tự động cắt bớt phần Lot lệnh ngoài vượt ngân sách Risk
input bool                  InpAutoAddExternalUnderRisk       = false;                    // [V12] Tự động bồi thêm Lot thiếu cho lệnh thăm dò Mobile
input double                InpMobileSyncMaxSlippagePct1R     = 15.0;                     // [V12] Độ lệch giá tối đa cho phép bồi thêm Lot Mobile (% 1R)
input bool                  InpNotifyExternalTrades           = true;                     // Gửi thông báo khi phát hiện mở/đóng lệnh từ Mobile

input group "=== 6. KIỂM SOÁT LỖ 3 TẦNG (RISK GUARD), MÃ PIN & EQUITY PROTECT ==="
input bool                  InpEnableRiskGuard                = true;                     // Bật hệ thống bảo vệ tài khoản 3 chu kỳ (Risk Guard)
input ENUM_ACTION_SCOPE     InpRiskControlScope               = SCOPE_ACCOUNT;            // Phạm vi bảo vệ và đóng lệnh của Risk Guard
input double                InpMaxDailyLossPct                = 2.0;                      // Hạn mức lỗ tối đa trong NGÀY (%)
input double                InpMaxWeeklyLossPct               = 4.0;                     // Hạn mức lỗ tối đa trong TUẦN (%)
input double                InpMaxMonthlyLossPct              = 6.0;                     // Hạn mức lỗ tối đa trong THÁNG (%)
input double                InpFallbackEquity                 = 100000.0;                 // Vốn dự phòng khi chưa chọn Live Equity ($)
input double                InpCooldownHours                  = 8.0;                      // Thời gian khóa hạ nhiệt sau khi chạm hạn mức lỗ (Giờ)
input bool                  InpEnableHalfRiskRec              = true;                     // Bật chế độ Phục hồi: Giảm 50% Risk sau khi hết Cooldown
input double                InpRecoveryTargetPct              = 1.0;                      // Mục tiêu lãi cần đạt để thoát chế độ Phục hồi (%)
input int                   InpMaxRecoveryOrders              = 1;                        // Số lệnh mở tối đa cùng lúc trong chế độ Phục hồi
input string                InpUnlockPinCode                  = "";                // Mã PIN mở khóa khẩn cấp (Để trống = bắt đặt trên UI)
input double                InpPinExtraBufferPct              = 1.5;                      // Hạn mức lỗ dự phòng cấp thêm sau khi mở khóa PIN (%)
input bool                  InpEnableEquityProtect            = true;                    // Bật bảo vệ vốn nổi tức thời (Equity Protect)
input ENUM_EQ_PROTECT_UNIT  InpEquityProtectUnit              = EQ_UNIT_EQUITY_PEAK;      // [V12] Đơn vị tính cho Equity Protect ($, %Bal, %Peak Eq)
input double                InpEquityDrawdownPct              = 5.0;                     // Ngưỡng cắt lỗ nổi / sụt giảm Equity tối đa
input double                InpEquityProfitTargetVal          = 0.0;                      // [V12] Ngưỡng chốt lời nổi tổng mục tiêu (0 = Tắt)
input ENUM_EQ_POST_ACTION   InpEquityProtectPostAction        = EQ_ACTION_LOCK_UNTIL_NEXT_DAY; // [V12] Hành động sau khi chạm Equity Protect
input bool                  InpEquityProtectAccountWide       = true;                    // Phạm vi Equity Protect (true = Toàn TK, false = Symbol)

input group "=== 7. LỌC TIN TỨC THEO THỨ/GIỜ & LỊCH GIAO DỊCH TUẦN 5 TÁC VỤ ==="
input bool                  InpEnableNewsFilter               = true;                     // Bật bộ lọc cấm giao dịch trong giờ tin tức
input ENUM_ACTION_SCOPE     InpNewsFilterScope                = SCOPE_ACCOUNT;            // Phạm vi hủy lệnh chờ khi vào vùng cấm tin
input ENUM_NEWS_TIME_ZONE   InpNewsTimeZone                   = TZ_MT5_SERVER;            // Múi giờ tham chiếu cho lịch tin (Server MT5 / Giờ máy)
input int                   InpMinBeforeNews                  = 2;                        // Số phút cấm giao dịch TRƯỚC giờ tin ra
input int                   InpMinAfterNews                   = 2;                        // Số phút cấm giao dịch SAU giờ tin ra
input bool                  InpEnableSlot1                    = true;                     // Bật Khung giờ tin tức số 1
input string                InpNewsSlot1                      = "19:30";                  // Giờ tin số 1 (Định dạng HH:MM)
input int                   InpNewsDaysMask1                  = 31;                       // [V12] Bitmask thứ áp dụng Tin 1 (31 = Thứ Hai..Thứ Sáu)
input bool                  InpEnableSlot2                    = false;                    // Bật Khung giờ tin tức số 2
input string                InpNewsSlot2                      = "21:00";                  // Giờ tin số 2 (Định dạng HH:MM)
input int                   InpNewsDaysMask2                  = 31;                       // [V12] Bitmask thứ áp dụng Tin 2
input bool                  InpEnableSlot3                    = false;                    // Bật Khung giờ tin tức số 3
input string                InpNewsSlot3                      = "22:30";                  // Giờ tin số 3 (Định dạng HH:MM)
input int                   InpNewsDaysMask3                  = 31;                       // [V12] Bitmask thứ áp dụng Tin 3
input bool                  InpEnableTimedFlatten             = false;                    // Bật tự động đóng lệnh cuối phiên mỗi ngày
input string                InpTimedFlattenServerTime         = "23:55";                  // Giờ máy chủ tự động đóng lệnh cuối ngày (HH:MM)
input bool                  InpEnableWeeklySchedule           = false;                    // Bật bộ hẹn giờ giao dịch lặp theo tuần (Time Manager)
input int                   InpWeeklyScheduleDaysMask         = 31;                       // Bitmask thứ thực thi lịch tuần (31 = Thứ Hai..Thứ Sáu)
input string                InpWeeklyScheduleTime             = "09:00";                  // Giờ máy chủ thực thi tác vụ tuần chính (HH:MM)
input ENUM_WEEKLY_ACTION    InpWeeklyScheduleAction           = WEEKLY_CLOSE_SYMBOL;      // Hành động của tác vụ tuần chính
input string                InpTimeManagerTasksPreset         = "";                       // [V12] Cấu hình mở rộng 5 tác vụ tuần (On,Days,HH:MM,Act;...)
input bool                  InpEnableAsyncGroupClose          = false;                     // [V12] Sử dụng OrderSendAsync tốc độ cao khi đóng hàng loạt

input group "=== 8. GIAO DIỆN KHUNG KÉP, 23 PHÍM TẮT, TELEGRAM PHOTO & CẦU NỐI STTS ==="
input ENUM_COLOR_THEME      InpColorTheme                     = THEME_COLORBLIND_SAFE;    // [V12] Chủ đề bảng màu (Mù màu Xanh-Cam / Kinh điển Xanh-Đỏ)
input int                   InpUiScalePct                     = 100;                      // [V12] Hệ số phóng đại giao diện (80% - 150%)
input bool                  InpShowAnchoredAtrLine            = true;                     // Hiển thị đường bậc thang ATR Neo & Spotlight T1/T2/T3
input bool                  InpShowSizerLines                 = true;                     // Hiển thị bộ đường kéo thả Entry / SL / TP & Vùng R
input int                   InpStartPanelX                    = 14;                       // Tọa độ X ban đầu của Bảng điều khiển (px)
input int                   InpStartPanelY                    = 82;                       // Tọa độ Y ban đầu của Bảng điều khiển (px)
input int                   InpFontSize                       = 9;                        // Cỡ chữ chuẩn trên giao diện và nhãn biểu đồ
input bool                  InpShowJournalSignals             = true;                     // Hiển thị ghim lệnh & đường nối lịch sử trên biểu đồ
input int                   InpJournalHistoryDays             = 3;                        // Số ngày lịch sử giao dịch vẽ trên biểu đồ
input bool                  InpAutoExportJournalCsv           = true;                     // Tự động xuất nhật ký giao dịch ra tệp CSV
input bool                  InpSyncSymbolAllCharts            = false;                    // [V12] Đồng bộ đổi Symbol cho toàn bộ biểu đồ đang mở
input bool                  InpAutoScreenshotOnTrade          = false;                    // [V12] Tự động chụp ảnh biểu đồ khi Mở/Đóng lệnh & T2/T3
input bool                  InpAlertOnScreen                  = false;                    // Bật cảnh báo Popup trên màn hình MT5
input bool                  InpAlertEmail                     = false;                    // Bật gửi cảnh báo qua Email MT5
input bool                  InpAlertPush                      = false;                    // Bật gửi thông báo đẩy (Push Notification) tới điện thoại
input bool                  InpTelegramEnabled                = false;                    // Bật gửi thông báo & báo cáo qua Telegram Bot
input string                InpTelegramBotToken               = "";                       // Telegram Bot Token (Lấy từ @BotFather)
input string                InpTelegramChatId                 = "";                       // Telegram Chat ID hoặc Channel ID nhận tin
input bool                  InpTelegramSendPhotoChart         = true;                     // [V12] Đính kèm ảnh chụp biểu đồ PNG qua API sendPhoto
input bool                  InpTelegramOnOpen                 = true;                     // Gửi Telegram khi có lệnh mới khớp
input bool                  InpTelegramOnClose                = true;                     // Gửi Telegram khi đóng vị thế
input bool                  InpTelegramOnPending              = true;                     // Gửi Telegram khi đặt / hủy lệnh chờ & OCO
input bool                  InpTelegramOnRiskLock             = true;                     // Gửi Telegram khi kích hoạt khóa Risk Guard / Equity Protect
input bool                  InpTelegramOnSR                   = true;                     // Gửi Telegram khi giá phá vỡ Hỗ trợ / Kháng cự
input bool                  InpTelegramOnSchedule             = true;                     // Gửi Telegram khi thực thi lịch hẹn giờ tuần
input bool                  InpEnableSupportResistanceAlerts  = false;                    // Bật cảnh báo phá vỡ đỉnh/đáy Hỗ trợ - Kháng cự
input int                   InpSRLookbackBars                 = 20;                       // Số nến dò vùng Hỗ trợ / Kháng cự
input int                   InpSRBreakBufferPoints            = 2;                        // Điểm đệm xác nhận phá vỡ Hỗ trợ / Kháng cự
input ENUM_TIMEFRAMES       InpSRTimeframe                    = PERIOD_CURRENT;           // Khung thời gian dò Hỗ trợ / Kháng cự
input ENUM_STTS_BRIDGE_MODE InpSttsBridgeMode                 = STTS_BRIDGE_OFF;          // [V12] Chế độ Cầu nối Chỉ báo Ngoài (STTS / iCustom)
input string                InpExtIndicatorName               = "Market\\Smart Trend Trading System"; // [V12] Đường dẫn tên chỉ báo ngoài
input int                   InpExtBuyBufferIdx                = 0;                        // [V12] Chỉ số Buffer tín hiệu MUA của chỉ báo ngoài
input int                   InpExtSellBufferIdx               = 1;                        // [V12] Chỉ số Buffer tín hiệu BÁN của chỉ báo ngoài
input bool                  InpEnableHotkeys                  = true;                     // Bật điều khiển nhanh bằng bàn phím (23 phím tắt)
input bool                  InpConfirmHotkeyTrades            = true;                     // Hỏi xác nhận trước khi vào lệnh bằng phím tắt
input string                InpHotkeyBuy                      = "B";                      // Phím tắt: Vào lệnh BUY
input string                InpHotkeySell                     = "S";                      // Phím tắt: Vào lệnh SELL
input string                InpHotkeyBreakEven                = "E";                      // Phím tắt: Dời SL về Hòa vốn (BE) ngay lập tức
input string                InpHotkeyCloseAll                 = "C";                      // Phím tắt: Đóng tất cả lệnh trên Symbol
input string                InpHotkeyCloseWinners             = "G";                      // Phím tắt: Đóng toàn bộ lệnh đang LỜI
input string                InpHotkeyCloseLosers              = "L";                      // Phím tắt: Đóng toàn bộ lệnh đang LỖ
input string                InpHotkeyOCO                      = "Shift+O";                // Phím tắt: Đặt nhanh cặp lệnh chờ OCO
input string                InpHotkeyDeletePending            = "H";                      // Phím tắt: Xóa toàn bộ lệnh chờ của EA
input string                InpHotkeyPendingOrder             = "P";                      // Phím tắt: Chuyển đổi kiểu lệnh (Market/Limit/Stop/LPO/StopLimit)
input string                InpHotkeyChangeDirection          = "R";                      // Phím tắt: Đảo chiều Setup dự kiến (Long <-> Short)
input string                InpHotkeyClosePartial             = "X";                      // Phím tắt: Đóng nhanh 50% khối lượng vị thế
input string                InpHotkeyCloseBuy                 = "Shift+N";                // Phím tắt: Đóng toàn bộ vị thế BUY
input string                InpHotkeyCloseSell                = "Shift+M";                // Phím tắt: Đóng toàn bộ vị thế SELL
input string                InpHotkeyTogglePanel              = "M";                      // Phím tắt: Thu gọn / Mở rộng Bảng điều khiển
input string                InpHotkeyDrawBuy                  = "D";                      // Phím tắt: Bật thước Sizer hướng BUY
input string                InpHotkeyDrawSell                 = "F";                      // Phím tắt: Bật thước Sizer hướng SELL
input string                InpHotkeyAutoAdjust               = "Shift+A";                // Phím tắt: Bật / Tắt tự động gắn SL/TP
input string                InpHotkeyPinSL                    = "Shift+S";                // Phím tắt: Ghim cố định mức SL hiện tại
input string                InpHotkeyPinTP                    = "Shift+T";                // Phím tắt: Ghim cố định mức TP hiện tại
input string                InpHotkeyPinAll                   = "Shift+F";                // Phím tắt: Ghim cố định toàn bộ Setup
input string                InpHotkeyRiskReward               = "Shift+R";                // Phím tắt: Hiển thị thông tin tỷ lệ R:R
input string                InpHotkeyNextSymbol               = "]";                      // Phím tắt: Chuyển sang Symbol kế tiếp trong Market Watch
input string                InpHotkeyPreviousSymbol           = "[";                      // Phím tắt: Quay lại Symbol trước đó trong Market Watch

input group "=== 9. [PATCH v12.1] TÍN HIỆU & CẢNH BÁO RỦI RO QUA TELEGRAM ==="
input bool                  InpTelegramOnSignal               = true;                     // Gửi Telegram thẻ tín hiệu STTS (cần Cầu nối = AUTO_SIGNAL)
input bool                  InpSttsAutoExecute                = false;                    // [NGUY HIỂM] Tự vào lệnh khi có tín hiệu STTS (cần Cầu nối = AUTO_SIGNAL)
input int                   InpSttsTrendExpireBars            = 20;                       // Xu hướng STTS về Trung lập sau N nến không có tín hiệu (0 = không hết hạn)
input bool                  InpRiskWarnEnabled                = true;                     // Bật cảnh báo sớm rủi ro (quota, margin, lệnh không SL)
input bool                  InpTelegramOnRiskWarn             = true;                     // Gửi cảnh báo rủi ro sớm qua Telegram
input string                InpRiskWarnLevels                 = "50,75,90";               // Các mốc % hạn mức Ngày/Tuần/Tháng đã dùng để cảnh báo (cách nhau dấu phẩy)
input double                InpMarginLevelWarnPct             = 200.0;                    // Cảnh báo khi Margin Level thấp hơn (%) (0 = tắt)
input int                   InpNakedPosWarnSec                = 30;                       // Cảnh báo vị thế không có SL sau N giây (0 = tắt)

// ============================================================================
// ĐỊNH NGHĨA CẤU TRÚC DỮ LIỆU CỐT LÕI (CORE DATA STRUCTURES V12)
// ============================================================================
struct SPartialTier
{
   bool                  enabled;      // Bật / Tắt tầng cắt này
   ENUM_TRIGGER_UNIT     triggerUnit;  // Đơn vị kích hoạt (RR, Points, %TP, Giá)
   double                triggerVal;   // Giá trị ngưỡng kích hoạt
   ENUM_PARTIAL_VOL_MODE volMode;      // Cơ sở tính khối lượng (% Lot gốc / % Lot còn lại)
   double                closePct;     // Phần trăm khối lượng cần đóng (1..100%)
};

struct SBeStage
{
   bool              enabled;      // Bật / Tắt tầng Breakeven này
   ENUM_TRIGGER_UNIT triggerUnit;  // Đơn vị kích hoạt (RR, Points, %TP, Giá)
   double            triggerVal;   // Ngưỡng kích hoạt
   ENUM_TRIGGER_UNIT lockUnit;     // Đơn vị khóa lãi (RR, Points, %TP, Giá)
   double            lockVal;      // Giá trị lợi nhuận khóa được
};

struct SMultiTrailStage
{
   bool   enabled;     // Bật / Tắt nấc Multi-Trail này
   double triggerPts;  // Mức lãi kích hoạt (Points)
   double distPts;     // Khoảng cách bám SL (Points)
   double stepPts;     // Bước nhảy tối thiểu (Points)
};

enum ENUM_VIRTUAL_ORD_STATE
{
   VORD_INACTIVE               = 0, // Khe lệnh ảo đang trống
   VORD_ACTIVE_WAIT_TOUCH      = 1, // Đang chờ giá chạm mức kích hoạt (Limit / Stop / StopLimit Pha 1 / LPO Pha 1)
   VORD_LPO_PHASE2_TRAIL_REV   = 2, // LPO Pha 2: Đã chạm vùng Limit, đang kéo Stop bám đỉnh/đáy sóng hồi
   VORD_STOPLIMIT_PHASE2_LIMIT = 3  // Stop-Limit Ảo Pha 2: Đã chạm giá Stop, đang chờ giá hồi về mức Limit
};

struct SVirtualOrder
{
   int                    slotId;        // Chỉ số khe (0..19)
   ENUM_VIRTUAL_ORD_STATE state;         // Trạng thái máy trạng thái lệnh ảo
   string                 symbol;        // Mã giao dịch
   bool                   isBuy;         // true = BUY, false = SELL
   ENUM_ORDER_ENTRY_MODE  mode;          // Kiểu lệnh (Limit, Stop, LPO, Stop-Limit)
   double                 entryPrice;    // Giá kích hoạt chính (hoặc vùng Limit của LPO)
   double                 stopLimitPrice;// Giá Limit thực thi (cho Stop-Limit) hoặc Giá Trigger động (cho LPO Pha 2)
   double                 slPrice;       // Mức Stop Loss mục tiêu
   double                 tpPrice;       // Mức Take Profit mục tiêu
   double                 lotSize;       // Khối lượng dự kiến (0 = tính động theo Risk lúc khớp)
   int                    pullbackPts;   // Khoảng cách bám sóng hồi LPO (Points)
   datetime               createdTime;   // Thời điểm khởi tạo
   datetime               expiryTime;    // Thời điểm hết hạn (0 = GTC)
   string                 ocoGroupId;    // Mã nhóm OCO liên kết (rỗng = độc lập)
};

struct STimeTask
{
   bool               enabled;      // Bật / Tắt tác vụ hẹn giờ này
   int                daysMask;     // Bitmask thứ trong tuần (Bit 0=Thứ Hai .. Bit 6=Chủ Nhật)
   string             timeStr;      // Chuỗi giờ thực thi "HH:MM"
   ENUM_WEEKLY_ACTION action;       // Hành động thực thi
   int                lastExecDate; // Khóa ngày đã chạy gần nhất (YYYYMMDD) chống chạy lặp
};

struct SArbiterDecision
{
   ulong  ticket;             // Ticket vị thế
   long   positionId;         // Định danh POSITION_IDENTIFIER bất biến
   bool   isBuy;              // Chiều vị thế
   bool   forceCloseFull;     // P1/P2/P3: Yêu cầu đóng 100% vị thế ngay lập tức
   string closeFullReason;    // Lý do đóng 100% vị thế
   double partialCloseVol;    // P3(T2)/P4: Tổng khối lượng cần đóng một phần trong chu kỳ này
   string partialCloseReason; // Lý do đóng một phần
   int    newTpMaskBits;      // Các bit tầng TP vừa hoàn tất cần ghi nhận
   int    newSlMaskBits;      // Các bit tầng SL vừa hoàn tất cần ghi nhận
   int    newBeMaskBits;      // Các bit tầng BE vừa hoàn tất cần ghi nhận
   bool   suppressHardTp;     // Cờ yêu cầu gỡ Hard TP trên máy chủ
   double candidateSL;        // Mức SL tốt nhất được đề xuất từ P5 (BE/Lock) và P6 (Trailing)
   string slWinnerSource;     // Tên module chiến thắng đề xuất SL
   double candidateTP;        // Mức TP đề xuất (hoặc 0.0 nếu gỡ Hard TP)
   bool   attachInitLevels;   // P7: Cờ gắn SL/TP khởi tạo lần đầu
};

struct SAtrCacheKey
{
   string                symbol;
   ENUM_TIMEFRAMES       calcTf;
   datetime              lastClosedBarTime;
   datetime              anchorTime;
   double                entryPriceParam;
   ENUM_TRADE_SIDE       sideParam;
   int                   atrLen;
   double                firstMul;
   double                atrMul;
   ENUM_ATR_CALC_SOURCE  atrSrc;
   ENUM_SWEEP_PROTECTION sweepMode;
   double                tierPct1R;
   int                   swingLookback;
   bool                  allowAutoRestart;
   double                trailStartRR;
};

struct STelegramQueueItem
{
   string text;
   string photoFile;
};

// ============================================================================
// BIẾN TOÀN CỤC RUNTIME & TIỀN TỐ ĐỐI TƯỢNG ĐỒ HỌA (GLOBAL STATE V12)
// ============================================================================
string PREFIX      = "EAP82_UI_";
string VIS_PREFIX  = "EAP82_VIS_";
string DRAG_PREFIX = "EAP82_SZ_";
string JRN_PREFIX  = "EAP82_JRN_";

ENUM_UI_TAB          g_activeTab        = TAB_POSITION;
ENUM_DRAWER_MODE     g_drawerMode       = DRAWER_CLOSED;
ENUM_COLOR_THEME     g_colorTheme       = THEME_COLORBLIND_SAFE;
double               g_uiScale          = 1.0;
bool                 g_isEditingTextField = false;
string               g_focusedEditName  = "";
datetime             g_lastCloseAllClickTime = 0; // Chống bấm nhầm nút ĐÓNG TẤT CẢ (xác nhận 2 lần trong 3 giây)
string               g_lastToastMsg     = "Hệ thống sẵn sàng.";
datetime             g_lastToastTime    = 0;

// --- Biến trạng thái ATR Neo & Chống quét 3 tầng ---
ENUM_ATR_TF_MODE      g_atrTfMode;
ENUM_TIMEFRAMES       g_resolvedAtrTf   = PERIOD_CURRENT;
bool                  g_autoSyncDate    = true;
int                   g_standbyLookback = 35;
ENUM_TRADE_SIDE       g_tradeSide;
int                   g_entryDateYear, g_entryDateMonth, g_entryDateDay;
double                g_entryPriceInput;
int                   g_atrLength;
double                g_atrMultiplier;
double                g_customValueForFirstDay;
ENUM_ATR_CALC_SOURCE  g_atrSource;
ENUM_SWEEP_PROTECTION g_sweepMode;
double                g_tierPctOf1R;
int                   g_swingLookback;
bool                  g_autoRestartAtr;

double                g_pineLatestAtr      = 0.0;
double                g_pineEntryLevel     = 0.0;
double                g_pineTrailingStop   = 0.0;
double                g_pineFirstBarSlDist = 0.0;
bool                  g_pineStopPlotting   = false;
bool                  g_pineStartCalc      = false;
int                   g_tier1SavedCount    = 0;
int                   g_tier2HalfCutCount  = 0;
SAtrCacheKey          g_atrCacheKey;
bool                  g_atrCacheValid      = false;
double                g_cachedTrailResult  = 0.0;

bool                  g_isTrailingArmedNow    = false;
bool                  g_mixedPositionFallback = false;
bool                  g_mixedModeWarningShown = false;
bool                  g_pinSizerEntry         = false;
bool                  g_showJournal           = true;
ulong                 g_lastLoggedDealId      = 0;

// --- Biến trạng thái Risk Guard 3 chu kỳ, Cooldown, Phục hồi & PIN ---
bool                  g_enRiskGuard;
double                g_maxDailyLossPct, g_maxWeeklyLossPct, g_maxMonthlyLossPct;
double                g_customEquity;
bool                  g_useLiveEquity    = true;
double                g_cooldownHours;
bool                  g_enHalfRiskRec;
double                g_recoveryTargetPct;
int                   g_maxRecOrders;
string                g_enteredPinStr    = "****";
datetime              g_breachTimestamp  = 0;
bool                  g_inCooldownLock   = false;
int                   g_cooldownRemSec   = 0;
bool                  g_inRecoveryMode   = false;
double                g_recStartMonthPct = 0.0;
double                g_pinExtraDayPct   = 0.0;
double                g_pinExtraWeekPct  = 0.0;
double                g_pinExtraMonthPct = 0.0;
int                   g_lastDayOfYear    = -1;
bool                  g_wasBreachedPrev  = false;

// --- Biến trạng thái Lọc tin tức & Lịch tuần ---
bool                  g_enNewsFilter;
ENUM_NEWS_TIME_ZONE   g_newsTz;
int                   g_minBeforeNews, g_minAfterNews;
bool                  g_enSlot1, g_enSlot2, g_enSlot3;
string                g_newsSlot1, g_newsSlot2, g_newsSlot3;
int                   g_newsDaysMask1 = 31, g_newsDaysMask2 = 31, g_newsDaysMask3 = 31;

// --- Biến trạng thái Định cỡ, Trailing, Ma trận 10 TP/SL & 4 BE ---
ENUM_SL_CALC_MODE     g_slMode;
ENUM_VOL_SLTP_RULE    g_volRule;
ENUM_MULTI_ORDER_MODE g_multiMode;
ENUM_TRAIL_STYLE      g_trailStyle;
ENUM_RISK_INPUT_MODE  g_riskInputMode;
ENUM_ADV_TRAIL_MODE   g_advTrailMode       = ADV_TRAIL_OFF;
int                   g_advTrailHandle     = INVALID_HANDLE;
ENUM_ADV_TRAIL_MODE   g_advTrailHandleMode = ADV_TRAIL_OFF;
datetime              g_lastAdvancedTrailBar = 0;

double                g_riskPct;
double                g_riskFixedCash;
double                g_riskCustomBase;
double                g_fixedCashSlBudget;
double                g_targetRR;
int                   g_manualSlPts;
int                   g_bufferPts;
double                g_commPerLot;
bool                  g_autoSlTp;

bool                  g_enPartial;
double                g_partialRR, g_partialPct;
bool                  g_enPartialSL;
SPartialTier          g_tpTiers[10];
SPartialTier          g_slTiers[10];
SBeStage              g_beStages[4];
SMultiTrailStage      g_multiTrailStages[4];
STimeTask             g_timeTasks[5];

bool                  g_enBe;
double                g_beRR;
int                   g_bePoints;
bool                  g_enCommonBe = true;
double                g_commonBePrice = 0.0;
bool                  g_enLock;
double                g_lockTrigRR, g_lockLvlRR;
bool                  g_enTrail;
double                g_trailStartRR;

bool                  g_showAtrPlot;
bool                  g_showSizer;

// --- Biến tọa độ & trạng thái Giao diện Khung Kép ---
int                   g_panelX            = 14;
int                   g_panelY            = 82;
int                   g_panelW            = 560;
int                   g_drawerW           = 340;
int                   g_panelH            = 620;
int                   g_headerH           = 28;
bool                  g_isDraggingPanel   = false;
int                   g_dragOffsetX       = 0;
int                   g_dragOffsetY       = 0;
bool                  g_prevMouseLeftDown = false;
int                   g_cornerPresetIdx   = 0;
int                   g_selectedPosRowIdx = -1; // Chọn dòng vị thế trong Tab MANAGE (-1 = áp cho cả nhóm)

// --- Biến đường kéo thả Sizer (Entry, SL, TP, StopLimit, LPO) ---
double                g_sizerEntryPrice     = 0.0;
double                g_sizerSlPrice        = 0.0;
double                g_sizerTpPrice        = 0.0;
double                g_sizerStopLimitPrice = 0.0; // Đường phụ cho lệnh Buy/Sell Stop Limit
double                g_pinnedSlDist        = 0.0;

// --- Biến quản lý tách bạch Entry kế hoạch vs Giá khớp thực tế, Khóa Setup & Chia 3 nhịp ---
double                g_plannedEntryPrice     = 0.0;
double                g_actualFillEntryPrice  = 0.0;
double                g_standbyLockedEntry    = 0.0;
double                g_standbyLockedSl       = 0.0;
double                g_standbyLockedTp       = 0.0;
double                g_standbyLocked1R       = 0.0;
datetime              g_standbyLockedAnchorTime = 0;
datetime              g_standbyLockedRefBarTime = 0;
ENUM_TIMEFRAMES       g_standbyLockedTf       = PERIOD_CURRENT;
bool                  g_standbySetupLocked    = false;
int                   g_prevOpenCountForSetup = 0;
double                g_enteredManualLot      = 0.0;
double                g_leg1SuggestedLot      = 0.0;
double                g_leg2SuggestedLot      = 0.0;
double                g_leg3SuggestedLot      = 0.0;
double                g_nextAddOnSuggestedLot = 0.0;
double                g_remainingSetupRiskPct = 0.0;
double                g_remainingSetupRiskCash= 0.0;
bool                  g_hardTpSuppressedForPartial = false;

// --- Biến trạng thái Khóa, Tự động hóa, Lệnh Ảo & Cầu nối STTS ---
bool                  g_isMinimized              = false;
bool                  g_manualForceLock          = false;
bool                  g_accountSwitchHold        = false;
bool                  g_accountHoldRiskDataReady = false;
long                  g_initAccountLogin         = 0;
int                   g_initServerHash           = 0;
bool                  g_riskBreached             = false;
bool                  g_riskDataAvailable        = true;
bool                  g_riskCloseNoticeShown     = false;
datetime              g_lastBulkCloseWarning     = 0;
string                g_breachReason             = "";
bool                  g_newsLockedState          = false;
string                g_newsStatusText           = "Đang kiểm tra lịch tin...";

int                   g_entryMode                = 0; // 0=Market, 1=Limit, 2=Stop, 3=LPO, 4=StopLimit, 5=OCO
ENUM_OCO_MODE         g_ocoMode                  = OCO_BREAKOUT_STOP_STOP;
int                   g_pullbackPoints           = 50;
int                   g_stopLimitOffsetPts       = 40;
double                g_maxLotPerOrder           = 0.0;
bool                  g_equityProtectOn          = false;
bool                  g_equityLatched            = false;
bool                  g_timeManagerOn            = false;
bool                  g_weeklyOn                 = false;
bool                  g_hotkeysOn                = false;
bool                  g_srAlertsOn               = false;
bool                  g_manageExternalOn         = false;
bool                  g_reduceExternalOn         = false;
bool                  g_addExternalOn            = false;
bool                  g_attachExternalSlTpOn     = false;
bool                  g_pendingTrailOn           = false;
bool                  g_virtualPendingActive     = false;
bool                  g_virtualTPOn              = false;
bool                  g_virtualSLOn              = false;
bool                  g_telegramOn               = false;
STelegramQueueItem    g_telegramQueue[];
datetime              g_lastTelegramErrorAt      = 0;
datetime              g_lastSRSignalBar          = 0;
double                g_previousSRBid            = 0.0;
double                g_previousSRAsk            = 0.0;

// --- Sổ 20 Lệnh Chờ Ảo & Tương thích ngược biến đơn ---
SVirtualOrder         g_virtualOrders[20];
double                g_virtualPendingEntry      = 0.0;
double                g_virtualPendingSL         = 0.0;
double                g_virtualPendingTP         = 0.0;
bool                  g_virtualPendingBuy        = true;
int                   g_virtualPendingMode       = 1;
datetime              g_virtualPendingCreated    = 0;
bool                  g_equityScopeAccount       = false;

// --- Trạng thái Cầu nối Chỉ báo Ngoài (STTS Bridge) ---
ENUM_STTS_BRIDGE_MODE g_sttsBridgeMode           = STTS_BRIDGE_OFF;
int                   g_sttsIndicatorHandle      = INVALID_HANDLE;
int                   g_sttsCurrentTrend         = 0; // +1 = Bullish, -1 = Bearish, 0 = Neutral
datetime              g_lastSttsSignalBar        = 0;
datetime              g_sttsTrendSetBar          = 0; // [v12.1] Nến đóng gần nhất có tín hiệu (để hết hạn xu hướng)

// --- Bảng màu Giao diện (Tự động cập nhật theo Theme) ---
color C_BG_HEADER   = C'15,23,42';
color C_BG_DRAG     = C'30,58,138';
color C_BG_BODY     = C'22,30,46';
color C_BG_HUD      = C'13,38,44';
color C_BG_CARD     = C'30,41,59';
color C_BORDER      = C'60,75,98';
color C_EDIT_BG     = C'248,250,252';
color C_EDIT_MUTED  = C'148,163,184';
color C_EDIT_TXT    = C'15,23,42';
color C_TAB_ACTIVE  = C'37,99,235';
color C_TAB_IDLE    = C'45,55,72';
color C_BTN_ON      = C'16,185,129';
color C_BTN_OFF     = C'71,85,105';
color C_BTN_LOCK    = C'185,28,28';
color C_BTN_BUY     = C'26,115,232';  // Mặc định Xanh dương (#1A73E8) thân thiện mù màu
color C_BTN_SELL    = C'250,144,62';  // Mặc định Cam hổ phách (#FA903E) thân thiện mù màu
color C_BTN_ACT     = C'217,119,6';
color C_BTN_MODE    = C'124,58,237';

color C_ATR_LONG    = C'0,255,157';
color C_ATR_SHORT   = C'255,64,129';
color C_TIER1_RAY   = clrGold;
color C_TIER2_RAY   = clrDeepSkyBlue;
color C_TIER3_RAY   = clrOrangeRed;

// ============================================================================
// MODULE 1: CConfigAndState (QUẢN LÝ CẤU HÌNH, BITMASK GV & LƯU TRỮ BỀN VỮNG)
// ============================================================================

//+------------------------------------------------------------------+
//| Áp dụng bảng màu giao diện theo chủ đề người dùng chọn           |
//+------------------------------------------------------------------+
void ApplyColorThemePalette()
{
   if(g_colorTheme == THEME_COLORBLIND_SAFE)
   {
      C_BTN_BUY   = C'26,115,232';  // #1A73E8 Blue
      C_BTN_SELL  = C'250,144,62';  // #FA903E Amber Orange
      C_ATR_LONG  = C'0,229,255';   // Cyan sáng
      C_ATR_SHORT = C'255,145,0';   // Cam sáng
   }
   else
   {
      C_BTN_BUY   = C'16,185,129';  // Xanh lá kinh điển
      C_BTN_SELL  = C'220,38,38';   // Đỏ kinh điển
      C_ATR_LONG  = C'0,255,157';
      C_ATR_SHORT = C'255,64,129';
   }
}

//+------------------------------------------------------------------+
//| Ghi nhận thông báo ngắn lên thanh Toast Bar ở đáy bảng điều khiển|
//+------------------------------------------------------------------+
void SetToastStatus(string message)
{
   g_lastToastMsg  = message;
   g_lastToastTime = TimeLocal();
   if(ObjectFind(0, PREFIX + "Toast_Txt") >= 0)
      ObjectSetString(0, PREFIX + "Toast_Txt", OBJPROP_TEXT,
                      "• " + message + " [" + TimeToString(g_lastToastTime, TIME_SECONDS) + "]");
}

//+------------------------------------------------------------------+
//| Trả về tên viết tắt của khung thời gian                          |
//+------------------------------------------------------------------+
string GetTfShortName(ENUM_TIMEFRAMES tf)
{
   ENUM_TIMEFRAMES realTf = (tf == PERIOD_CURRENT) ? _Period : tf;
   switch(realTf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      default:         return EnumToString(realTf);
   }
}

//+------------------------------------------------------------------+
//| Tính mã băm tên máy chủ để cô lập GlobalVariable giữa các sàn   |
//+------------------------------------------------------------------+
int GetCurrentServerHash()
{
   string server = AccountInfoString(ACCOUNT_SERVER);
   long serverHash = 0;
   for(int i = 0; i < StringLen(server); i++)
      serverHash = (serverHash * 31 + (long)StringGetCharacter(server, i)) % 2147483647;
   return (int)serverHash;
}

//+------------------------------------------------------------------+
//| Sinh khóa GlobalVariable gắn theo Tài khoản & Server (<=63 ký tự)|
//+------------------------------------------------------------------+
string AccountScopedGV(string key)
{
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   long accountHash = ((login % 2147483647) * 31 + (long)GetCurrentServerHash()) % 2147483647;
   if(accountHash < 0) accountHash = -accountHash;
   string prefix = "E85_" + IntegerToString(accountHash) + "_";
   string fullKey = prefix + key;
   if(StringLen(fullKey) <= 63)
      return fullKey;

   long keyHash = 0;
   for(int i = 0; i < StringLen(key); i++)
      keyHash = (keyHash * 31 + (long)StringGetCharacter(key, i)) % 2147483647;
   string suffix = "_" + IntegerToString(keyHash);
   int keepLength = 63 - StringLen(prefix) - StringLen(suffix);
   if(keepLength < 1) keepLength = 1;
   return prefix + StringSubstr(key, 0, keepLength) + suffix;
}

//+------------------------------------------------------------------+
//| Các hàm quản lý Bitmask nguyên tử cho 10 cấp TP, 10 SL, 4 BE     |
//+------------------------------------------------------------------+
string PartialTpMaskKey(long positionId) { return AccountScopedGV("PTPMASK_" + IntegerToString(positionId)); }
string PartialSlMaskKey(long positionId) { return AccountScopedGV("PSLMASK_" + IntegerToString(positionId)); }
string StepBeMaskKey(long positionId)    { return AccountScopedGV("BEMASK_"  + IntegerToString(positionId)); }
string InitialVolKey(long positionId)    { return AccountScopedGV("INITVOL_" + IntegerToString(positionId)); }

int GetPositionBitmask(string gvKey)
{
   if(!GlobalVariableCheck(gvKey))
      return 0;
   return (int)MathRound(GlobalVariableGet(gvKey));
}

bool IsTierBitSet(string gvKey, int tierIndexZeroBased)
{
   if(tierIndexZeroBased < 0 || tierIndexZeroBased > 29)
      return false;
   int mask = GetPositionBitmask(gvKey);
   return ((mask & (1 << tierIndexZeroBased)) != 0);
}

void SetTierBit(string gvKey, int tierIndexZeroBased)
{
   if(tierIndexZeroBased < 0 || tierIndexZeroBased > 29)
      return;
   int mask = GetPositionBitmask(gvKey);
   mask |= (1 << tierIndexZeroBased);
   GlobalVariableSet(gvKey, (double)mask);
}

void ClearPositionMasks(long positionId)
{
   GlobalVariableDel(PartialTpMaskKey(positionId));
   GlobalVariableDel(PartialSlMaskKey(positionId));
   GlobalVariableDel(StepBeMaskKey(positionId));
   GlobalVariableDel(InitialVolKey(positionId));
}

//+------------------------------------------------------------------+
//| Các khóa GlobalVariable cho Virtual SL / Virtual TP              |
//+------------------------------------------------------------------+
string VirtualSLPositionKey(long positionId)          { return AccountScopedGV("TD_VSL_"    + IntegerToString(positionId)); }
string VirtualEmergencySLPositionKey(long positionId) { return AccountScopedGV("TD_VSLEM_"  + IntegerToString(positionId)); }
string VirtualSLOrderKey(ulong orderTicket)           { return AccountScopedGV("TD_VSLORD_" + IntegerToString((long)orderTicket)); }
string VirtualEmergencySLOrderKey(ulong orderTicket)  { return AccountScopedGV("TD_VSLEMOD_"+ IntegerToString((long)orderTicket)); }
string VirtualTPPositionKey(long positionId)          { return AccountScopedGV("TD_VTP_"    + IntegerToString(positionId)); }
string VirtualTPOrderKey(ulong orderTicket)           { return AccountScopedGV("TD_VTPORD_" + IntegerToString((long)orderTicket)); }

//+------------------------------------------------------------------+
//| Lấy mức Stop Loss hiệu dụng của vị thế đang chọn (Ưu tiên V-SL)  |
//+------------------------------------------------------------------+
double SelectedPositionStopForLogic()
{
   double brokerSL = PositionGetDouble(POSITION_SL);
   long positionId = PositionGetInteger(POSITION_IDENTIFIER);
   string key = VirtualSLPositionKey(positionId);
   if(GlobalVariableCheck(key))
   {
      double virtualSL = GlobalVariableGet(key);
      if(virtualSL > 0.0)
         return virtualSL;
   }
   return brokerSL;
}

string LockGVKey(string suffix)
{
   return AccountScopedGV("EAP85_LK_" + suffix);
}

string AccountContextGVKey(string suffix)
{
   return "EAP85_CTX_" + IntegerToString((long)ChartID()) + "_" + suffix;
}

//+------------------------------------------------------------------+
//| Lưu và nạp trạng thái khóa Risk Guard vào GlobalVariable         |
//+------------------------------------------------------------------+
void SaveLockStateToGV()
{
   GlobalVariableSet(LockGVKey("TIME"),      (double)g_breachTimestamp);
   GlobalVariableSet(LockGVKey("REC_MODE"),  g_inRecoveryMode ? 1.0 : 0.0);
   GlobalVariableSet(LockGVKey("REC_START"), g_recStartMonthPct);
   GlobalVariableSet(LockGVKey("PIN_EX_D"),  g_pinExtraDayPct);
   GlobalVariableSet(LockGVKey("PIN_EX_W"),  g_pinExtraWeekPct);
   GlobalVariableSet(LockGVKey("PIN_EX_M"),  g_pinExtraMonthPct);
   GlobalVariableSet(LockGVKey("LAST_DOY"),  (double)g_lastDayOfYear);
   GlobalVariableSet(LockGVKey("MAN_LOCK"),  g_manualForceLock ? 1.0 : 0.0);
}

void LoadLockStateFromGV()
{
   if(GlobalVariableCheck(LockGVKey("TIME")))      g_breachTimestamp  = (datetime)GlobalVariableGet(LockGVKey("TIME"));
   if(GlobalVariableCheck(LockGVKey("REC_MODE")))  g_inRecoveryMode   = (GlobalVariableGet(LockGVKey("REC_MODE")) > 0.5);
   if(GlobalVariableCheck(LockGVKey("REC_START"))) g_recStartMonthPct = GlobalVariableGet(LockGVKey("REC_START"));
   if(GlobalVariableCheck(LockGVKey("PIN_EX_D")))  g_pinExtraDayPct   = GlobalVariableGet(LockGVKey("PIN_EX_D"));
   if(GlobalVariableCheck(LockGVKey("PIN_EX_W")))  g_pinExtraWeekPct  = GlobalVariableGet(LockGVKey("PIN_EX_W"));
   if(GlobalVariableCheck(LockGVKey("PIN_EX_M")))  g_pinExtraMonthPct = GlobalVariableGet(LockGVKey("PIN_EX_M"));
   if(GlobalVariableCheck(LockGVKey("LAST_DOY")))  g_lastDayOfYear    = (int)GlobalVariableGet(LockGVKey("LAST_DOY"));
   if(GlobalVariableCheck(LockGVKey("MAN_LOCK")))  g_manualForceLock  = (GlobalVariableGet(LockGVKey("MAN_LOCK")) > 0.5);
}

//+------------------------------------------------------------------+
//| Đồng bộ các ô Ngày/Tháng/Năm Neo ATR theo thời gian tham chiếu    |
//+------------------------------------------------------------------+
void SyncAnchorDateFields(ENUM_TIMEFRAMES activeTf, datetime openOrderTime)
{
   if(!g_autoSyncDate)
      return;

   datetime latestTfBarTime = iTime(_Symbol, activeTf, 0);
   datetime refTime = (latestTfBarTime > 0) ? latestTfBarTime : TimeCurrent();
   if(openOrderTime > 0 && openOrderTime > refTime)
      refTime = openOrderTime;

   if(refTime <= 0)
      return;

   MqlDateTime dt;
   TimeToStruct(refTime, dt);

   bool changed = (g_entryDateYear != dt.year || g_entryDateMonth != dt.mon || g_entryDateDay != dt.day);
   g_entryDateYear  = dt.year;
   g_entryDateMonth = dt.mon;
   g_entryDateDay   = dt.day;

   if(changed || g_activeTab == TAB_TRAILING)
   {
      if(ObjectFind(0, PREFIX + "Ed_Yr") >= 0)
         ObjectSetString(0, PREFIX + "Ed_Yr", OBJPROP_TEXT, IntegerToString(g_entryDateYear));
      if(ObjectFind(0, PREFIX + "Ed_Mo") >= 0)
         ObjectSetString(0, PREFIX + "Ed_Mo", OBJPROP_TEXT, IntegerToString(g_entryDateMonth));
      if(ObjectFind(0, PREFIX + "Ed_Dy") >= 0)
         ObjectSetString(0, PREFIX + "Ed_Dy", OBJPROP_TEXT, IntegerToString(g_entryDateDay));
   }
}

//+------------------------------------------------------------------+
//| Quản lý khóa Setup lúc chờ lệnh (Standby Setup Lock)             |
//+------------------------------------------------------------------+
string StandbySetupGVKey(string suffix)
{
   return AccountScopedGV("EAP85_STBY_" + _Symbol + "_" + suffix);
}

void SaveStandbySetupToGV()
{
   if(!g_standbySetupLocked)
      return;
   GlobalVariableSet(StandbySetupGVKey("LOCKED"), 1.0);
   GlobalVariableSet(StandbySetupGVKey("TF"),     (double)g_standbyLockedTf);
   GlobalVariableSet(StandbySetupGVKey("ANC_T"),  (double)g_standbyLockedAnchorTime);
   GlobalVariableSet(StandbySetupGVKey("BAR_T"),  (double)g_standbyLockedRefBarTime);
   GlobalVariableSet(StandbySetupGVKey("ENTRY"),  g_standbyLockedEntry);
   GlobalVariableSet(StandbySetupGVKey("SL"),     g_standbyLockedSl);
   GlobalVariableSet(StandbySetupGVKey("TP"),     g_standbyLockedTp);
   GlobalVariableSet(StandbySetupGVKey("1R"),     g_standbyLocked1R);
   GlobalVariableSet(StandbySetupGVKey("SIDE"),   (double)g_tradeSide);
}

bool LoadStandbySetupFromGV()
{
   if(!GlobalVariableCheck(StandbySetupGVKey("LOCKED")) || GlobalVariableGet(StandbySetupGVKey("LOCKED")) < 0.5)
      return false;
   int tfVal = (int)GlobalVariableGet(StandbySetupGVKey("TF"));
   if(tfVal <= 0)
      return false;
   g_standbyLockedTf         = (ENUM_TIMEFRAMES)tfVal;
   g_standbyLockedAnchorTime = (datetime)GlobalVariableGet(StandbySetupGVKey("ANC_T"));
   g_standbyLockedRefBarTime = (datetime)GlobalVariableGet(StandbySetupGVKey("BAR_T"));
   g_standbyLockedEntry      = GlobalVariableGet(StandbySetupGVKey("ENTRY"));
   g_standbyLockedSl         = GlobalVariableGet(StandbySetupGVKey("SL"));
   g_standbyLockedTp         = GlobalVariableGet(StandbySetupGVKey("TP"));
   g_standbyLocked1R         = GlobalVariableGet(StandbySetupGVKey("1R"));
   g_standbySetupLocked      = (g_standbyLockedEntry > 0.0 && g_standbyLocked1R > 0.0);
   return g_standbySetupLocked;
}

void ResetStandbySetupLock(ENUM_TIMEFRAMES preferredTf = PERIOD_CURRENT)
{
   g_standbySetupLocked      = false;
   g_standbyLockedEntry      = 0.0;
   g_standbyLockedSl         = 0.0;
   g_standbyLockedTp         = 0.0;
   g_standbyLocked1R         = 0.0;
   g_standbyLockedAnchorTime = 0;
   g_standbyLockedRefBarTime = 0;
   ENUM_TIMEFRAMES baseTf = (preferredTf == PERIOD_CURRENT) ? _Period : preferredTf;
   if(g_atrTfMode == ATR_TF_FIXED_H1)       baseTf = PERIOD_H1;
   else if(g_atrTfMode == ATR_TF_FIXED_M15) baseTf = PERIOD_M15;
   else if(g_atrTfMode == ATR_TF_FIXED_M5)  baseTf = PERIOD_M5;
   else if(g_atrTfMode == ATR_TF_FIXED_H4)  baseTf = PERIOD_H4;
   else if(g_atrTfMode == ATR_TF_FIXED_D1)  baseTf = PERIOD_D1;
   g_standbyLockedTf = baseTf;
   GlobalVariableDel(StandbySetupGVKey("LOCKED"));
   GlobalVariableDel(StandbySetupGVKey("TF"));
   GlobalVariableDel(StandbySetupGVKey("ANC_T"));
   GlobalVariableDel(StandbySetupGVKey("BAR_T"));
   GlobalVariableDel(StandbySetupGVKey("ENTRY"));
   GlobalVariableDel(StandbySetupGVKey("SL"));
   GlobalVariableDel(StandbySetupGVKey("TP"));
   GlobalVariableDel(StandbySetupGVKey("1R"));
   GlobalVariableDel(StandbySetupGVKey("SIDE"));
}

//+------------------------------------------------------------------+
//| Phân tích chuỗi cấu hình 10 tầng Partial TP / SL từ Input        |
//| Định dạng mỗi tầng: "Enabled,Unit,TriggerVal,ClosePct"           |
//+------------------------------------------------------------------+
void ParsePartialMatrixPreset(string presetStr, SPartialTier &tiers[], ENUM_PARTIAL_VOL_MODE defaultVolMode, bool isTpMatrix)
{
   for(int i = 0; i < 10; i++)
   {
      tiers[i].enabled     = false;
      tiers[i].triggerUnit = UNIT_RR;
      tiers[i].triggerVal  = isTpMatrix ? (1.0 + i * 0.5) : (0.10 * (i + 1));
      tiers[i].volMode     = defaultVolMode;
      tiers[i].closePct    = 10.0;
   }

   string clean = presetStr;
   StringTrimLeft(clean);
   StringTrimRight(clean);
   if(clean == "")
      return;

   string rows[];
   int rowCount = StringSplit(clean, ';', rows);
   for(int r = 0; r < rowCount && r < 10; r++)
   {
      string cols[];
      int colCount = StringSplit(rows[r], ',', cols);
      if(colCount >= 4)
      {
         tiers[r].enabled     = (StringToInteger(cols[0]) != 0);
         int u                = (int)StringToInteger(cols[1]);
         tiers[r].triggerUnit = (u >= 0 && u <= 3) ? (ENUM_TRIGGER_UNIT)u : UNIT_RR;
         tiers[r].triggerVal  = MathMax(0.01, StringToDouble(cols[2]));
         tiers[r].closePct    = MathMax(1.0, MathMin(100.0, StringToDouble(cols[3])));
      }
      else if(colCount == 3)
      {
         tiers[r].enabled     = true;
         int u                = (int)StringToInteger(cols[0]);
         tiers[r].triggerUnit = (u >= 0 && u <= 3) ? (ENUM_TRIGGER_UNIT)u : UNIT_RR;
         tiers[r].triggerVal  = MathMax(0.01, StringToDouble(cols[1]));
         tiers[r].closePct    = MathMax(1.0, MathMin(100.0, StringToDouble(cols[2])));
      }
   }
}

//+------------------------------------------------------------------+
//| Khởi tạo 4 tầng Breakeven và 4 tầng Multi-Trail từ Inputs        |
//+------------------------------------------------------------------+
void InitBeAndMultiTrailMatrices()
{
   double trigR[4] = { InpStepBE1TriggerR, InpStepBE2TriggerR, InpStepBE3TriggerR, InpStepBE4TriggerR };
   double lockR[4] = { InpStepBE1LockR,    InpStepBE2LockR,    InpStepBE3LockR,    InpStepBE4LockR };
   for(int i = 0; i < 4; i++)
   {
      g_beStages[i].enabled     = (InpEnableStepBreakEven && trigR[i] > 0.0);
      g_beStages[i].triggerUnit = InpStepBeTriggerUnit;
      g_beStages[i].triggerVal  = trigR[i];
      g_beStages[i].lockUnit    = InpStepBeLockUnit;
      g_beStages[i].lockVal     = lockR[i];
   }

   double defGain[4] = { 200.0, 400.0, 600.0, 1000.0 };
   double defDist[4] = { 150.0, 100.0,  70.0,   40.0 };
   double defStep[4] = {  20.0,  15.0,  10.0,    5.0 };
   for(int j = 0; j < 4; j++)
   {
      g_multiTrailStages[j].enabled    = true;
      g_multiTrailStages[j].triggerPts = defGain[j];
      g_multiTrailStages[j].distPts    = defDist[j];
      g_multiTrailStages[j].stepPts    = defStep[j];
   }

   string rows[];
   int cnt = StringSplit(InpMultiTrailPreset4, ';', rows);
   for(int r = 0; r < cnt && r < 4; r++)
   {
      string cols[];
      if(StringSplit(rows[r], ',', cols) >= 3)
      {
         g_multiTrailStages[r].enabled    = true;
         g_multiTrailStages[r].triggerPts = MathMax(1.0, StringToDouble(cols[0]));
         g_multiTrailStages[r].distPts    = MathMax(1.0, StringToDouble(cols[1]));
         g_multiTrailStages[r].stepPts    = MathMax(1.0, StringToDouble(cols[2]));
      }
   }
}

//+------------------------------------------------------------------+
//| Khởi tạo 5 tác vụ hẹn giờ tuần (Trade Time Manager)              |
//+------------------------------------------------------------------+
void InitTimeManagerTasks()
{
   for(int i = 0; i < 5; i++)
   {
      g_timeTasks[i].enabled      = false;
      g_timeTasks[i].daysMask     = 31;
      g_timeTasks[i].timeStr      = "09:00";
      g_timeTasks[i].action       = WEEKLY_CLOSE_SYMBOL;
      g_timeTasks[i].lastExecDate = 0;
   }
   // Tác vụ 0 lấy từ tham số Input chính để tương thích ngược
   g_timeTasks[0].enabled  = InpEnableWeeklySchedule;
   g_timeTasks[0].daysMask = InpWeeklyScheduleDaysMask;
   g_timeTasks[0].timeStr  = InpWeeklyScheduleTime;
   g_timeTasks[0].action   = InpWeeklyScheduleAction;

   if(InpTimeManagerTasksPreset != "")
   {
      string rows[];
      int cnt = StringSplit(InpTimeManagerTasksPreset, ';', rows);
      for(int r = 0; r < cnt && r < 5; r++)
      {
         string cols[];
         if(StringSplit(rows[r], ',', cols) >= 4)
         {
            g_timeTasks[r].enabled  = (StringToInteger(cols[0]) != 0);
            g_timeTasks[r].daysMask = (int)StringToInteger(cols[1]);
            g_timeTasks[r].timeStr  = cols[2];
            int act                 = (int)StringToInteger(cols[3]);
            if(act >= 0 && act <= 5)
               g_timeTasks[r].action = (ENUM_WEEKLY_ACTION)act;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Đồng bộ các cờ phụ thuộc khi thay đổi kiểu Trailing chính        |
//+------------------------------------------------------------------+
void ApplyTrailStyleFlags()
{
   if(g_trailStyle == TRAIL_STYLE_AUTO_ATR)
   {
      g_enTrail = true;
   }
   else if(g_trailStyle == TRAIL_STYLE_BE_FLOAT)
   {
      g_enTrail = false;
      g_enBe    = true;
   }
   else
   {
      g_enTrail = false;
      g_enBe    = false;
      g_enLock  = false;
   }
}

//+------------------------------------------------------------------+
//| Khởi tạo toàn bộ biến Runtime từ các nhóm Input                  |
//+------------------------------------------------------------------+
void InitParamsFromInputs()
{
   g_colorTheme      = InpColorTheme;
   ApplyColorThemePalette();
   g_uiScale         = MathMax(0.80, MathMin(1.50, InpUiScalePct / 100.0));

   g_atrTfMode       = InpAtrTfMode;
   g_resolvedAtrTf   = _Period;
   g_autoSyncDate    = InpAutoSyncAnchorDate;
   g_standbyLookback = MathMax(10, InpStandbyLookbackBars);

   g_tradeSide       = InpTradeSide;
   g_entryDateYear   = InpEntryDateYear;
   g_entryDateMonth  = InpEntryDateMonth;
   g_entryDateDay    = InpEntryDateDay;
   if(g_autoSyncDate)
      SyncAnchorDateFields(_Period, 0);

   g_entryPriceInput         = InpCustomEntryPrice;
   g_atrLength               = MathMax(1, InpAtrLength);
   g_atrMultiplier           = InpAtrMultiplier;
   g_customValueForFirstDay  = InpCustomValueForFirstDay;
   g_atrSource               = InpAtrCalcSource;
   g_sweepMode               = InpSweepProtection;
   g_tierPctOf1R             = MathMax(5.0, MathMin(InpTierBufferPctOf1R, 90.0));
   g_swingLookback           = MathMax(1, InpSwingLookbackBars);
   g_autoRestartAtr          = InpAutoRestartAtrOnBreak;
   g_atrCacheValid           = false;

   g_enRiskGuard       = InpEnableRiskGuard;
   g_maxDailyLossPct   = InpMaxDailyLossPct;
   g_maxWeeklyLossPct  = InpMaxWeeklyLossPct;
   g_maxMonthlyLossPct = InpMaxMonthlyLossPct;
   double realEq       = AccountInfoDouble(ACCOUNT_EQUITY);
   g_useLiveEquity     = (realEq > 0.0);
   g_customEquity      = (realEq > 0.0) ? NormalizeDouble(realEq, 0) : InpFallbackEquity;

   g_cooldownHours     = InpCooldownHours;
   g_enHalfRiskRec     = InpEnableHalfRiskRec;
   g_recoveryTargetPct = InpRecoveryTargetPct;
   g_maxRecOrders      = MathMax(1, InpMaxRecoveryOrders);
   g_enteredPinStr     = "****";

   g_enNewsFilter      = InpEnableNewsFilter;
   g_newsTz            = InpNewsTimeZone;
   g_minBeforeNews     = InpMinBeforeNews;
   g_minAfterNews      = InpMinAfterNews;
   g_enSlot1           = InpEnableSlot1;
   g_newsSlot1         = InpNewsSlot1;
   g_newsDaysMask1     = InpNewsDaysMask1;
   g_enSlot2           = InpEnableSlot2;
   g_newsSlot2         = InpNewsSlot2;
   g_newsDaysMask2     = InpNewsDaysMask2;
   g_enSlot3           = InpEnableSlot3;
   g_newsSlot3         = InpNewsSlot3;
   g_newsDaysMask3     = InpNewsDaysMask3;

   g_slMode            = InpSlCalcMode;
   g_volRule           = InpVolSlTpRule;
   g_multiMode         = InpMultiOrderMode;
   g_trailStyle        = InpTrailStyle;
   g_riskInputMode     = InpRiskInputMode;
   g_advTrailMode      = InpAdvancedTrailMode;
   g_riskPct           = InpRiskPerTradePct;
   g_riskFixedCash     = MathMax(0.0, InpRiskFixedCash);
   g_riskCustomBase    = MathMax(0.0, InpRiskCustomBase);
   g_fixedCashSlBudget = MathMax(1.0, InpFixedCashSlBudget);
   g_targetRR          = InpTargetRR;
   g_manualSlPts       = InpManualSlPoints;
   g_bufferPts         = InpBufferPoints;
   g_commPerLot        = InpCommissionPerLot;
   g_autoSlTp          = InpAutoAttachSlTp;
   g_showJournal       = InpShowJournalSignals;

   g_enPartial         = InpEnablePartialTP;
   g_partialRR         = MathMax(0.1, InpPartialAtRR);
   g_partialPct        = MathMax(1.0, MathMin(99.0, InpPartialClosePct));
   g_enPartialSL       = InpEnablePartialSL;

   ParsePartialMatrixPreset(InpPartialTpMatrixPreset, g_tpTiers, InpPartialTpVolMode, true);
   // Đồng bộ tầng 1 của Ma trận TP với tham số đơn để tương thích ngược hoàn toàn
   g_tpTiers[0].enabled     = g_enPartial;
   g_tpTiers[0].triggerUnit = UNIT_RR;
   g_tpTiers[0].triggerVal  = g_partialRR;
   g_tpTiers[0].closePct    = g_partialPct;

   ParsePartialMatrixPreset(InpPartialSlMatrixPreset, g_slTiers, VOL_PCT_INITIAL, false);
   InitBeAndMultiTrailMatrices();
   InitTimeManagerTasks();

   g_enBe              = InpEnableBe;
   g_beRR              = InpBeTriggerRR;
   g_bePoints          = InpBePlusPoints;
   g_enCommonBe        = InpEnableCommonBe;

   g_enLock            = InpEnableLockProfit;
   g_lockTrigRR        = InpLockTriggerRR;
   g_lockLvlRR         = InpLockLevelRR;

   g_trailStartRR      = MathMax(0.0, InpTrailingStartRR);
   ApplyTrailStyleFlags();

   g_showAtrPlot       = InpShowAnchoredAtrLine;
   g_showSizer         = InpShowSizerLines;
   g_pullbackPoints    = MathMax(1, InpPullbackDistancePoints);
   g_stopLimitOffsetPts= MathMax(1, InpStopLimitOffsetPoints);
   g_ocoMode           = InpOcoDefaultMode;
   g_maxLotPerOrder    = MathMax(0.0, InpMaxLotPerOrder);
   g_virtualTPOn       = InpEnableVirtualTakeProfit;
   g_virtualSLOn       = InpEnableVirtualStopLoss;
   g_telegramOn        = InpTelegramEnabled;
   g_weeklyOn          = InpEnableWeeklySchedule;
   g_hotkeysOn         = InpEnableHotkeys;
   g_srAlertsOn        = InpEnableSupportResistanceAlerts;
   g_sttsBridgeMode    = InpSttsBridgeMode;

   g_manageExternalOn      = (InpManageExternalTrades || InpAutoReduceExternalOverRisk || InpAutoAddExternalUnderRisk || InpAutoAttachExternalSlTp);
   g_reduceExternalOn      = InpAutoReduceExternalOverRisk;
   g_addExternalOn         = InpAutoAddExternalUnderRisk;
   g_attachExternalSlTpOn  = InpAutoAttachExternalSlTp;
   g_equityProtectOn       = InpEnableEquityProtect;
   g_timeManagerOn         = InpEnableTimedFlatten;
   g_pendingTrailOn        = InpEnablePendingTrailing;
   g_equityScopeAccount    = InpEquityProtectAccountWide;

   for(int v = 0; v < 20; v++)
   {
      g_virtualOrders[v].slotId = v;
      g_virtualOrders[v].state  = VORD_INACTIVE;
   }

   g_enteredManualLot = MathMax(0.0, InpEnteredManualLot);
   if(!LoadStandbySetupFromGV())
   {
      ENUM_TIMEFRAMES initTf = _Period;
      if(g_atrTfMode == ATR_TF_FIXED_H1)       initTf = PERIOD_H1;
      else if(g_atrTfMode == ATR_TF_FIXED_M15) initTf = PERIOD_M15;
      else if(g_atrTfMode == ATR_TF_FIXED_M5)  initTf = PERIOD_M5;
      else if(g_atrTfMode == ATR_TF_FIXED_H4)  initTf = PERIOD_H4;
      else if(g_atrTfMode == ATR_TF_FIXED_D1)  initTf = PERIOD_D1;
      g_standbyLockedTf = initTf;
   }

   g_panelX = InpStartPanelX;
   g_panelY = InpStartPanelY;
}

//+------------------------------------------------------------------+
//| Lưu và Nạp Profile cài đặt (GV + Tệp .tdp trong MQL5/Files)      |
//+------------------------------------------------------------------+
string TradeDeskProfileKey(string item)
{
   return AccountScopedGV("TD_PROFILE_" + _Symbol + "_" + item);
}

void SaveTradeDeskProfile()
{
   GlobalVariableSet(TradeDeskProfileKey("RISK"),       g_riskPct);
   GlobalVariableSet(TradeDeskProfileKey("RISKMODE"),   (double)g_riskInputMode);
   GlobalVariableSet(TradeDeskProfileKey("RISKFIX"),    g_riskFixedCash);
   GlobalVariableSet(TradeDeskProfileKey("RISKCUSTOM"), g_riskCustomBase);
   GlobalVariableSet(TradeDeskProfileKey("ADVTRAIL"),   (double)g_advTrailMode);
   GlobalVariableSet(TradeDeskProfileKey("RR"),         g_targetRR);
   GlobalVariableSet(TradeDeskProfileKey("SLMODE"),     (double)g_slMode);
   GlobalVariableSet(TradeDeskProfileKey("MANSL"),      (double)g_manualSlPts);
   GlobalVariableSet(TradeDeskProfileKey("BUFFER"),     (double)g_bufferPts);
   GlobalVariableSet(TradeDeskProfileKey("SIDE"),       (double)g_tradeSide);
   GlobalVariableSet(TradeDeskProfileKey("ENTRYMODE"),  (double)g_entryMode);
   GlobalVariableSet(TradeDeskProfileKey("OCOMODE"),    (double)g_ocoMode);
   GlobalVariableSet(TradeDeskProfileKey("TRAILSTYLE"), (double)g_trailStyle);
   GlobalVariableSet(TradeDeskProfileKey("TRAILRR"),    g_trailStartRR);
   GlobalVariableSet(TradeDeskProfileKey("PARTIAL"),    g_enPartial ? 1.0 : 0.0);
   GlobalVariableSet(TradeDeskProfileKey("PARTRR"),     g_partialRR);
   GlobalVariableSet(TradeDeskProfileKey("PARTPCT"),    g_partialPct);
   GlobalVariableSet(TradeDeskProfileKey("PARTSL"),     g_enPartialSL ? 1.0 : 0.0);
   GlobalVariableSet(TradeDeskProfileKey("BE"),         g_enBe ? 1.0 : 0.0);
   GlobalVariableSet(TradeDeskProfileKey("BERR"),       g_beRR);
   GlobalVariableSet(TradeDeskProfileKey("BEPTS"),      (double)g_bePoints);
   GlobalVariableSet(TradeDeskProfileKey("COMBE"),      g_enCommonBe ? 1.0 : 0.0);
   GlobalVariableSet(TradeDeskProfileKey("LOCK"),       g_enLock ? 1.0 : 0.0);
   GlobalVariableSet(TradeDeskProfileKey("LOCKTRIG"),   g_lockTrigRR);
   GlobalVariableSet(TradeDeskProfileKey("LOCKRR"),     g_lockLvlRR);
   GlobalVariableSet(TradeDeskProfileKey("ATRPER"),     (double)g_atrLength);
   GlobalVariableSet(TradeDeskProfileKey("ATRMUL"),     g_atrMultiplier);
   GlobalVariableSet(TradeDeskProfileKey("FIRSTMUL"),   g_customValueForFirstDay);
   GlobalVariableSet(TradeDeskProfileKey("NEWS"),       g_enNewsFilter ? 1.0 : 0.0);
   GlobalVariableSet(TradeDeskProfileKey("JOURNAL"),    g_showJournal ? 1.0 : 0.0);
   GlobalVariableSet(TradeDeskProfileKey("SIZER"),      g_showSizer ? 1.0 : 0.0);
   GlobalVariableSet(TradeDeskProfileKey("ATRLINE"),    g_showAtrPlot ? 1.0 : 0.0);
   GlobalVariableSet(TradeDeskProfileKey("VTPON"),      g_virtualTPOn ? 1.0 : 0.0);
   GlobalVariableSet(TradeDeskProfileKey("VSLON"),      g_virtualSLOn ? 1.0 : 0.0);
   GlobalVariableSet(TradeDeskProfileKey("THEME"),      (double)g_colorTheme);

   // Lưu đồng thời ra tệp cấu hình .tdp để lưu trữ bền vững toàn bộ ma trận 10 tầng
   string fileName = "TradeDeskPro_Profile_" + _Symbol + ".tdp";
   int h = FileOpen(fileName, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h != INVALID_HANDLE)
   {
      for(int i = 0; i < 10; i++)
      {
         FileWriteString(h, StringFormat("TP_TIER_%d=%d,%d,%.4f,%.2f\r\n",
                         i, g_tpTiers[i].enabled ? 1 : 0, (int)g_tpTiers[i].triggerUnit,
                         g_tpTiers[i].triggerVal, g_tpTiers[i].closePct));
         FileWriteString(h, StringFormat("SL_TIER_%d=%d,%d,%.4f,%.2f\r\n",
                         i, g_slTiers[i].enabled ? 1 : 0, (int)g_slTiers[i].triggerUnit,
                         g_slTiers[i].triggerVal, g_slTiers[i].closePct));
      }
      for(int b = 0; b < 4; b++)
      {
         FileWriteString(h, StringFormat("BE_STAGE_%d=%d,%d,%.4f,%d,%.4f\r\n",
                         b, g_beStages[b].enabled ? 1 : 0, (int)g_beStages[b].triggerUnit,
                         g_beStages[b].triggerVal, (int)g_beStages[b].lockUnit, g_beStages[b].lockVal));
      }
      FileClose(h);
   }

   SetToastStatus("Đã lưu Profile & Ma trận cho " + _Symbol);
   Alert("TuanProtrade: Đã lưu Profile và Ma trận 10 tầng cho " + _Symbol + ".");
}

bool ReadTradeDeskProfileValue(string item, double &value)
{
   string key = TradeDeskProfileKey(item);
   if(!GlobalVariableCheck(key))
      return false;
   value = GlobalVariableGet(key);
   return true;
}

void LoadTradeDeskProfile()
{
   double value = 0.0;
   if(!ReadTradeDeskProfileValue("RISK", value))
   {
      Alert("TuanProtrade: Chưa có Profile lưu cho " + _Symbol + ".");
      return;
   }
   g_riskPct = value;
   if(ReadTradeDeskProfileValue("RISKMODE", value))   { int v = (int)value; if(v >= 0 && v <= 7) g_riskInputMode = (ENUM_RISK_INPUT_MODE)v; }
   if(ReadTradeDeskProfileValue("RISKFIX", value))    g_riskFixedCash  = MathMax(0.0, value);
   if(ReadTradeDeskProfileValue("RISKCUSTOM", value)) g_riskCustomBase = MathMax(0.0, value);
   if(ReadTradeDeskProfileValue("ADVTRAIL", value))   { int v = (int)value; if(v >= 0 && v <= 8) { g_advTrailMode = (ENUM_ADV_TRAIL_MODE)v; g_advTrailHandleMode = ADV_TRAIL_OFF; } }
   if(ReadTradeDeskProfileValue("RR", value))         g_targetRR       = value;
   if(ReadTradeDeskProfileValue("SLMODE", value))     { int v = (int)value; if(v >= 0 && v <= 4) g_slMode = (ENUM_SL_CALC_MODE)v; }
   if(ReadTradeDeskProfileValue("MANSL", value))      g_manualSlPts    = (int)value;
   if(ReadTradeDeskProfileValue("BUFFER", value))     g_bufferPts      = (int)value;
   if(ReadTradeDeskProfileValue("SIDE", value))       g_tradeSide      = (value > 0.5) ? SIDE_SHORT : SIDE_LONG;
   if(ReadTradeDeskProfileValue("ENTRYMODE", value))  { int v = (int)value; if(v >= 0 && v <= 5) g_entryMode = v; }
   if(ReadTradeDeskProfileValue("OCOMODE", value))    { int v = (int)value; if(v >= 0 && v <= 4) g_ocoMode = (ENUM_OCO_MODE)v; }
   if(ReadTradeDeskProfileValue("TRAILSTYLE", value)) { int v = (int)value; if(v >= 0 && v <= 2) g_trailStyle = (ENUM_TRAIL_STYLE)v; }
   if(ReadTradeDeskProfileValue("TRAILRR", value))    g_trailStartRR   = value;
   if(ReadTradeDeskProfileValue("PARTIAL", value))    g_enPartial      = (value > 0.5);
   if(ReadTradeDeskProfileValue("PARTRR", value))     g_partialRR      = value;
   if(ReadTradeDeskProfileValue("PARTPCT", value))    g_partialPct     = value;
   if(ReadTradeDeskProfileValue("PARTSL", value))     g_enPartialSL    = (value > 0.5);
   if(ReadTradeDeskProfileValue("BE", value))         g_enBe           = (value > 0.5);
   if(ReadTradeDeskProfileValue("BERR", value))       g_beRR           = value;
   if(ReadTradeDeskProfileValue("BEPTS", value))      g_bePoints       = (int)value;
   if(ReadTradeDeskProfileValue("COMBE", value))      g_enCommonBe     = (value > 0.5);
   if(ReadTradeDeskProfileValue("LOCK", value))       g_enLock         = (value > 0.5);
   if(ReadTradeDeskProfileValue("LOCKTRIG", value))   g_lockTrigRR     = value;
   if(ReadTradeDeskProfileValue("LOCKRR", value))     g_lockLvlRR      = value;
   if(ReadTradeDeskProfileValue("ATRPER", value))     g_atrLength      = MathMax(1, (int)value);
   if(ReadTradeDeskProfileValue("ATRMUL", value))     g_atrMultiplier  = value;
   if(ReadTradeDeskProfileValue("FIRSTMUL", value))   g_customValueForFirstDay = value;
   if(ReadTradeDeskProfileValue("NEWS", value))       g_enNewsFilter   = (value > 0.5);
   if(ReadTradeDeskProfileValue("JOURNAL", value))    g_showJournal    = (value > 0.5);
   if(ReadTradeDeskProfileValue("SIZER", value))      g_showSizer      = (value > 0.5);
   if(ReadTradeDeskProfileValue("ATRLINE", value))    g_showAtrPlot    = (value > 0.5);
   if(ReadTradeDeskProfileValue("VTPON", value))      g_virtualTPOn    = (value > 0.5);
   if(ReadTradeDeskProfileValue("VSLON", value))      g_virtualSLOn    = (value > 0.5);
   if(ReadTradeDeskProfileValue("THEME", value))      { g_colorTheme = (value > 0.5) ? THEME_CLASSIC_GREENRED : THEME_COLORBLIND_SAFE; ApplyColorThemePalette(); }

   // Nạp lại tệp .tdp nếu tồn tại
   string fileName = "TradeDeskPro_Profile_" + _Symbol + ".tdp";
   if(FileIsExist(fileName))
   {
      int h = FileOpen(fileName, FILE_READ | FILE_TXT | FILE_ANSI);
      if(h != INVALID_HANDLE)
      {
         while(!FileIsEnding(h))
         {
            string line = FileReadString(h);
            int eqPos = StringFind(line, "=");
            if(eqPos <= 0) continue;
            string k = StringSubstr(line, 0, eqPos);
            string v = StringSubstr(line, eqPos + 1);
            if(StringFind(k, "TP_TIER_") == 0)
            {
               int idx = (int)StringToInteger(StringSubstr(k, 8));
               string cols[];
               if(idx >= 0 && idx < 10 && StringSplit(v, ',', cols) >= 4)
               {
                  g_tpTiers[idx].enabled     = (StringToInteger(cols[0]) != 0);
                  g_tpTiers[idx].triggerUnit = (ENUM_TRIGGER_UNIT)StringToInteger(cols[1]);
                  g_tpTiers[idx].triggerVal  = StringToDouble(cols[2]);
                  g_tpTiers[idx].closePct    = StringToDouble(cols[3]);
               }
            }
            else if(StringFind(k, "SL_TIER_") == 0)
            {
               int idx = (int)StringToInteger(StringSubstr(k, 8));
               string cols[];
               if(idx >= 0 && idx < 10 && StringSplit(v, ',', cols) >= 4)
               {
                  g_slTiers[idx].enabled     = (StringToInteger(cols[0]) != 0);
                  g_slTiers[idx].triggerUnit = (ENUM_TRIGGER_UNIT)StringToInteger(cols[1]);
                  g_slTiers[idx].triggerVal  = StringToDouble(cols[2]);
                  g_slTiers[idx].closePct    = StringToDouble(cols[3]);
               }
            }
            else if(StringFind(k, "BE_STAGE_") == 0)
            {
               int idx = (int)StringToInteger(StringSubstr(k, 9));
               string cols[];
               if(idx >= 0 && idx < 4 && StringSplit(v, ',', cols) >= 5)
               {
                  g_beStages[idx].enabled     = (StringToInteger(cols[0]) != 0);
                  g_beStages[idx].triggerUnit = (ENUM_TRIGGER_UNIT)StringToInteger(cols[1]);
                  g_beStages[idx].triggerVal  = StringToDouble(cols[2]);
                  g_beStages[idx].lockUnit    = (ENUM_TRIGGER_UNIT)StringToInteger(cols[3]);
                  g_beStages[idx].lockVal     = StringToDouble(cols[4]);
               }
            }
         }
         FileClose(h);
      }
   }

   ApplyTrailStyleFlags();
   g_atrCacheValid = false;
   if(CountPositionsInScope(false) == 0)
      ResetStandbySetupLock(_Period);
   SetToastStatus("Đã nạp Profile cho " + _Symbol);
   Alert("TuanProtrade: Đã nạp thành công Profile cho " + _Symbol + ".");
}

//+------------------------------------------------------------------+
//| Dọn dẹp các biến GlobalVariable cũ quá 30 ngày (Garbage Collect) |
//+------------------------------------------------------------------+
void GarbageCollectOldGVs()
{
   datetime cutoff = TimeCurrent() - 30 * 86400;
   int total = GlobalVariablesTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      string name = GlobalVariableName(i);
      if(StringFind(name, "E85_") != 0)
         continue;
      if(IsProtectedGVName(name))   // [v12.1] PIN, Profile, Lock, mask của lệnh còn sống
         continue;
      datetime lastAccess = GlobalVariableTime(name);
      if(lastAccess > 0 && lastAccess < cutoff)
         GlobalVariableDel(name);
   }
}

// ============================================================================
// MODULE 2: CSymbolMathAndSizing (TOÁN HỌC SYMBOL, 8 RISK BASIS & ĐỊNH CỠ LOT)
// ============================================================================

//+------------------------------------------------------------------+
//| Ánh xạ mã giao dịch thực thi (hỗ trợ Custom Symbol Renko / Giây) |
//+------------------------------------------------------------------+
string GetExecutionSymbol()
{
   string customExec = InpExecutionUnderlyingSymbol;
   StringTrimLeft(customExec);
   StringTrimRight(customExec);
   if(customExec != "" && SymbolSelect(customExec, true))
      return customExec;

   // Nếu chạy trên Custom Symbol bị khóa giao dịch (ví dụ EURUSD_Renko), tự động cắt hậu tố tìm mã gốc
   long tradeMode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
   {
      int underscore = StringFind(_Symbol, "_");
      if(underscore > 2)
      {
         string baseSym = StringSubstr(_Symbol, 0, underscore);
         if(SymbolSelect(baseSym, true))
            return baseSym;
      }
   }
   return _Symbol;
}

//+------------------------------------------------------------------+
//| Pha trộn màu với nền biểu đồ để vẽ vùng Risk / Reward bán trong  |
//+------------------------------------------------------------------+
color BlendWithBg(color fg, double alphaPct)
{
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   double a = MathMax(0.05, MathMin(alphaPct / 100.0, 0.45));
   int bgR = (bg & 0xFF), bgG = ((bg >> 8) & 0xFF), bgB = ((bg >> 16) & 0xFF);
   int fgR = (fg & 0xFF), fgG = ((fg >> 8) & 0xFF), fgB = ((fg >> 16) & 0xFF);
   int r = (int)MathRound(bgR * (1.0 - a) + fgR * a);
   int g = (int)MathRound(bgG * (1.0 - a) + fgG * a);
   int b = (int)MathRound(bgB * (1.0 - a) + fgB * a);
   return (color)(r | (g << 8) | (b << 16));
}

//+------------------------------------------------------------------+
//| Chuẩn hóa mức giá theo đúng bước nhảy SYMBOL_TRADE_TICK_SIZE     |
//+------------------------------------------------------------------+
double NormalizePriceToTickSize(string symbol, double price)
{
   if(price <= 0.0)
      return price;
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0)
      tickSize = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(tickSize <= 0.0)
      return NormalizeDouble(price, digits);
   double snapped = (double)MathRound(price / tickSize) * tickSize;
   return NormalizeDouble(snapped, digits);
}

//+------------------------------------------------------------------+
//| Tính số chữ số thập phân của bước khối lượng (Lot Step)          |
//+------------------------------------------------------------------+
int GetStepDigits(double step)
{
   if(step <= 0.0)
      return 2;
   int digits = 0;
   double temp = step;
   while(MathAbs(MathRound(temp) - temp) > 1e-6 && digits < 8)
   {
      temp *= 10.0;
      digits++;
   }
   return digits;
}

//+------------------------------------------------------------------+
//| Làm tròn khối lượng XUỐNG theo bước Lot của sàn (FloorLotStep)   |
//+------------------------------------------------------------------+
double FloorLotStep(double rawLot)
{
   string execSym = GetExecutionSymbol();
   double step = SymbolInfoDouble(execSym, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(execSym, SYMBOL_VOLUME_MAX);
   if(step <= 0.0)
      step = 0.01;
   double lots = MathFloor((rawLot + step * 1e-9) / step) * step;
   if(lots < minL)
      return 0.0;
   if(lots > maxL)
      lots = maxL;
   return NormalizeDouble(lots, GetStepDigits(step));
}

//+------------------------------------------------------------------+
//| Kiểm tra một vị thế có đủ khối lượng để tách đóng một phần không |
//+------------------------------------------------------------------+
bool CanSplitVolume(double volume, double closePercent)
{
   string execSym = GetExecutionSymbol();
   double minLot = SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN);
   if(volume <= 0.0 || closePercent <= 0.0 || closePercent >= 100.0 || minLot <= 0.0)
      return false;
   double closeVolume = FloorLotStep(volume * closePercent / 100.0);
   return (closeVolume >= minLot && volume - closeVolume >= minLot - 1e-6);
}

//+------------------------------------------------------------------+
//| Cảnh báo có giới hạn tần suất (Throttled Alert) chống spam log   |
//+------------------------------------------------------------------+
string GetSymbolAlertKey()
{
   long symbolHash = 0;
   for(int i = 0; i < StringLen(_Symbol); i++)
      symbolHash = (symbolHash * 31 + (long)StringGetCharacter(_Symbol, i)) % 2147483647;
   return IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + IntegerToString(symbolHash);
}

void AlertThrottled(string key, string message, int cooldownSeconds = 60)
{
   string gvKey = AccountScopedGV("EAP82_ALERT_" + key + "_" + GetSymbolAlertKey());
   datetime now = TimeLocal();
   datetime lastAlert = GlobalVariableCheck(gvKey) ? (datetime)GlobalVariableGet(gvKey) : 0;
   if(lastAlert > 0 && now - lastAlert < cooldownSeconds)
      return;
   GlobalVariableSet(gvKey, (double)now);
   SetToastStatus(message);
   Alert(message);
}

void NotifyQuotaRestored(string title, string detail)
{
   string fullMsg = StringFormat("EA [%s - %s]: %s", _Symbol, title, detail);
   SetToastStatus(title);
   Alert(fullMsg);
   SendNotification(fullMsg);
   PlaySound("ok.wav");
   if(InpTelegramOnRiskLock)   // [v12.1] gửi thêm Telegram khi mở khóa / phục hồi hạn mức
      TgEnqueueOnly(fullMsg, "");
}

//+------------------------------------------------------------------+
//| Ước tính rủi ro tiền tệ tại mức SL bằng hàm chuẩn OrderCalcProfit|
//+------------------------------------------------------------------+
bool EstimateStopRiskCash(string symbol, bool isLong, double volume, double entryPrice,
                          double stopPrice, int bufferPoints, double commissionPerLot, double &riskCash)
{
   riskCash = 0.0;
   if(symbol == "" || volume <= 0.0 || entryPrice <= 0.0 || stopPrice <= 0.0)
      return false;

   string calcSym = (symbol == _Symbol) ? GetExecutionSymbol() : symbol;
   double point = SymbolInfoDouble(calcSym, SYMBOL_POINT);
   if(point <= 0.0)
      return false;

   double bufferedStop = stopPrice + (isLong ? -1.0 : 1.0) * MathMax(0, bufferPoints) * point;
   double pnlAtStop = 0.0;
   ENUM_ORDER_TYPE orderType = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(orderType, calcSym, volume, entryPrice, bufferedStop, pnlAtStop))
      return false;

   // Nếu SL đã dời vào vùng có lãi, rủi ro giá bằng 0 nhưng vẫn cộng phí hoa hồng dự kiến
   riskCash = MathMax(0.0, -pnlAtStop) + MathMax(0.0, commissionPerLot) * volume;
   return true;
}

//+------------------------------------------------------------------+
//| Giải phương trình tìm khoảng cách SL từ ngân sách chịu lỗ/lot   |
//+------------------------------------------------------------------+
double FindStopDistanceForRiskBudget(string symbol, bool isLong, double entryPrice,
                                     double budgetPerLot, int bufferPoints, double commissionPerLot)
{
   string calcSym = (symbol == _Symbol) ? GetExecutionSymbol() : symbol;
   double point    = SymbolInfoDouble(calcSym, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(calcSym, SYMBOL_TRADE_TICK_SIZE);
   double distance = MathMax(point, tickSize);
   if(point <= 0.0 || distance <= 0.0 || entryPrice <= 0.0 || budgetPerLot <= 0.0)
      return 0.0;

   double zeroDistanceRisk = 0.0;
   if(!EstimateStopRiskCash(calcSym, isLong, 1.0, entryPrice, entryPrice, bufferPoints, commissionPerLot, zeroDistanceRisk)
      || zeroDistanceRisk > budgetPerLot)
      return 0.0;

   double low = 0.0, high = distance;
   bool bracketed = false;
   for(int i = 0; i < 48; i++)
   {
      double stop = entryPrice + (isLong ? -high : high);
      if(stop <= 0.0)
         return 0.0;
      double risk = 0.0;
      if(!EstimateStopRiskCash(calcSym, isLong, 1.0, entryPrice, stop, bufferPoints, commissionPerLot, risk))
         return 0.0;
      if(risk > budgetPerLot)
      {
         bracketed = true;
         break;
      }
      low = high;
      high *= 2.0;
   }
   if(!bracketed)
      return 0.0;

   for(int i = 0; i < 52; i++)
   {
      double mid = (low + high) * 0.5;
      double stop = entryPrice + (isLong ? -mid : mid);
      double risk = 0.0;
      if(stop <= 0.0 || !EstimateStopRiskCash(calcSym, isLong, 1.0, entryPrice, stop, bufferPoints, commissionPerLot, risk))
         return 0.0;
      if(risk <= budgetPerLot)
         low = mid;
      else
         high = mid;
   }
   return low;
}

//+------------------------------------------------------------------+
//| Tái tạo Balance cuối kỳ trước (Hôm qua / Tuần trước / Tháng trước)|
//+------------------------------------------------------------------+
bool GetPreviousPeriodBalance(ENUM_TIMEFRAMES period, double &balanceAtPeriodStart)
{
   balanceAtPeriodStart = 0.0;
   datetime now = TimeTradeServer();
   if(now <= 0) now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   if(period == PERIOD_D1)
   {
      // Đầu ngày hiện tại 00:00:00 tương đương thời điểm đóng cửa ngày hôm qua
   }
   else if(period == PERIOD_W1)
   {
      // Đầu tuần (Thứ Hai 00:00:00)
   }
   else if(period == PERIOD_MN1)
   {
      dt.day = 1;
   }
   else
      return false;

   datetime midnight = StructToTime(dt);
   datetime periodStart = midnight;
   if(period == PERIOD_W1)
   {
      MqlDateTime dow;
      TimeToStruct(now, dow);
      int daysFromMonday = (dow.day_of_week + 6) % 7;
      datetime approximateMonday = midnight - (datetime)(daysFromMonday * 86400);
      MqlDateTime monday;
      TimeToStruct(approximateMonday, monday);
      monday.hour = 0; monday.min = 0; monday.sec = 0;
      periodStart = StructToTime(monday);
   }
   if(periodStart <= 0 || periodStart > now || !HistorySelect(periodStart, now))
      return false;

   double currentPeriodBalanceDelta = 0.0;
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      currentPeriodBalanceDelta += HistoryDealGetDouble(deal, DEAL_PROFIT)
                                 + HistoryDealGetDouble(deal, DEAL_COMMISSION)
                                 + HistoryDealGetDouble(deal, DEAL_SWAP)
                                 + HistoryDealGetDouble(deal, DEAL_FEE);
   }
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   balanceAtPeriodStart = currentBalance - currentPeriodBalanceDelta;
   return (balanceAtPeriodStart > 0.0 && MathIsValidNumber(balanceAtPeriodStart));
}

//+------------------------------------------------------------------+
//| Lấy mức Equity hiệu dụng & Phần trăm rủi ro đang kích hoạt       |
//+------------------------------------------------------------------+
double GetEffectiveEquity()
{
   if(g_useLiveEquity)
   {
      double liveEq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(liveEq > 0.0)
         return liveEq;
   }
   if(g_customEquity > 0.0)
      return g_customEquity;
   double realEq = AccountInfoDouble(ACCOUNT_EQUITY);
   return (realEq > 0.0) ? realEq : InpFallbackEquity;
}

double GetActiveRiskPercent()
{
   if(g_inRecoveryMode && g_enHalfRiskRec)
      return NormalizeDouble(g_riskPct * 0.5, 2);
   return g_riskPct;
}

string GetRiskInputModeText()
{
   if(g_riskInputMode == RISK_INPUT_CASH)                  return "TIỀN CỐ ĐỊNH ($)";
   if(g_riskInputMode == RISK_INPUT_BALANCE_PCT)           return "% BALANCE";
   if(g_riskInputMode == RISK_INPUT_EQUITY_PCT)            return "% EQUITY";
   if(g_riskInputMode == RISK_INPUT_FREEMARGIN_PCT)        return "% FREE MARGIN";
   if(g_riskInputMode == RISK_INPUT_CUSTOM_PCT)            return "% VỐN TÙY CHỈNH";
   if(g_riskInputMode == RISK_INPUT_PREVDAY_BALANCE_PCT)   return "% BAL HÔM QUA";
   if(g_riskInputMode == RISK_INPUT_PREVWEEK_BALANCE_PCT)  return "% BAL TUẦN TRƯỚC";
   return "% BAL THÁNG TRƯỚC";
}

//+------------------------------------------------------------------+
//| Tính ngân sách rủi ro ($) cho tỷ trọng lệnh theo 8 chế độ vốn    |
//+------------------------------------------------------------------+
bool GetRiskCashBudgetForShare(double riskShare, double &budget, string &reason)
{
   budget = 0.0;
   reason = "";
   double base = 0.0;
   bool isCash = (g_riskInputMode == RISK_INPUT_CASH);
   switch(g_riskInputMode)
   {
      case RISK_INPUT_CASH:
         base = g_riskFixedCash;
         break;
      case RISK_INPUT_BALANCE_PCT:
         base = AccountInfoDouble(ACCOUNT_BALANCE);
         break;
      case RISK_INPUT_EQUITY_PCT:
         base = GetEffectiveEquity();
         break;
      case RISK_INPUT_FREEMARGIN_PCT:
         base = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
         break;
      case RISK_INPUT_CUSTOM_PCT:
         base = g_riskCustomBase;
         break;
      case RISK_INPUT_PREVDAY_BALANCE_PCT:
         if(!GetPreviousPeriodBalance(PERIOD_D1, base))
         { reason = "Không xác minh được Balance cuối ngày trước từ lịch sử MT5"; return false; }
         break;
      case RISK_INPUT_PREVWEEK_BALANCE_PCT:
         if(!GetPreviousPeriodBalance(PERIOD_W1, base))
         { reason = "Không xác minh được Balance cuối tuần trước từ lịch sử MT5"; return false; }
         break;
      case RISK_INPUT_PREVMONTH_BALANCE_PCT:
         if(!GetPreviousPeriodBalance(PERIOD_MN1, base))
         { reason = "Không xác minh được Balance cuối tháng trước từ lịch sử MT5"; return false; }
         break;
      default:
         reason = "Chế độ tính Risk không hợp lệ";
         return false;
   }
   if(base <= 0.0 || !MathIsValidNumber(base))
   {
      reason = "Cơ sở tính Risk bằng 0 hoặc chưa hợp lệ";
      return false;
   }
   if(g_enRiskGuard && !g_riskDataAvailable)
   {
      reason = "Dữ liệu lịch sử Risk Guard chưa đồng bộ xong";
      return false;
   }
   double activeAmount = isCash ? base : (base * GetActiveRiskPercent() / 100.0);
   if(isCash && g_inRecoveryMode && g_enHalfRiskRec)
      activeAmount *= 0.5;
   budget = activeAmount * MathMax(0.0, riskShare);
   if(budget <= 0.0)
   {
      reason = "Ngân sách rủi ro tính ra bằng 0";
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Hỗ trợ đọc đúng giá khớp mục tiêu của cả lệnh chờ Stop-Limit     |
//+------------------------------------------------------------------+
bool IsBuyPendingType(long orderType)
{
   return (orderType == ORDER_TYPE_BUY_LIMIT ||
           orderType == ORDER_TYPE_BUY_STOP  ||
           orderType == ORDER_TYPE_BUY_STOP_LIMIT);
}

double GetPendingOrderEffectiveEntry(ulong orderTicket)
{
   if(!OrderSelect(orderTicket))
      return 0.0;
   long type = OrderGetInteger(ORDER_TYPE);
   if(type == ORDER_TYPE_BUY_STOP_LIMIT || type == ORDER_TYPE_SELL_STOP_LIMIT)
   {
      double stopLimitPx = OrderGetDouble(ORDER_PRICE_STOPLIMIT);
      if(stopLimitPx > 0.0)
         return stopLimitPx;
   }
   return OrderGetDouble(ORDER_PRICE_OPEN);
}

//+------------------------------------------------------------------+
//| Tính tổng rủi ro đang mở trên Symbol hiện tại & Toàn tài khoản   |
//+------------------------------------------------------------------+
bool CalculateChartSymbolExposureRisk(double &riskCash, double &riskVolume, bool includePending)
{
   riskCash   = 0.0;
   riskVolume = 0.0;
   bool known = true;
   string execSym = GetExecutionSymbol();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string posSym = PositionGetString(POSITION_SYMBOL);
      if(posSym != _Symbol && posSym != execSym) continue;

      double sl = (InpVirtualSlSizingBasis == VSL_SIZE_BY_VIRTUAL_STOP)
                  ? SelectedPositionStopForLogic()
                  : PositionGetDouble(POSITION_SL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      bool isLong   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double oneRisk = 0.0;
      if(sl <= 0.0 || !EstimateStopRiskCash(posSym, isLong, volume, entry, sl, g_bufferPts, g_commPerLot, oneRisk))
         known = false;
      else
         riskCash += oneRisk;
      riskVolume += volume;
   }

   if(includePending)
   {
      for(int j = OrdersTotal() - 1; j >= 0; j--)
      {
         ulong ticket = OrderGetTicket(j);
         if(ticket == 0) continue;
         string ordSym = OrderGetString(ORDER_SYMBOL);
         if(ordSym != _Symbol && ordSym != execSym) continue;

         long type     = OrderGetInteger(ORDER_TYPE);
         double sl     = OrderGetDouble(ORDER_SL);
         double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
         double entry  = GetPendingOrderEffectiveEntry(ticket);
         double oneRisk = 0.0;
         bool isLong   = IsBuyPendingType(type);
         bool stopOnLossSide = isLong ? (sl < entry) : (sl > entry);
         if(sl <= 0.0 || !stopOnLossSide || !EstimateStopRiskCash(ordSym, isLong, volume, entry, sl, g_bufferPts, g_commPerLot, oneRisk))
            known = false;
         else
            riskCash += oneRisk;
         riskVolume += volume;
      }
   }
   return known;
}

bool CalculateAccountExposureRisk(double &riskCash)
{
   riskCash = 0.0;
   bool known = true;
   string execSym = GetExecutionSymbol();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string symbol = PositionGetString(POSITION_SYMBOL);
      double sl     = PositionGetDouble(POSITION_SL);
      if(InpVirtualSlSizingBasis == VSL_SIZE_BY_VIRTUAL_STOP)
      {
         long pid = PositionGetInteger(POSITION_IDENTIFIER);
         string vslK = VirtualSLPositionKey(pid);
         if(GlobalVariableCheck(vslK) && GlobalVariableGet(vslK) > 0.0)
            sl = GlobalVariableGet(vslK);
      }
      double volume = PositionGetDouble(POSITION_VOLUME);
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      bool isLong   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      int buffer    = (symbol == _Symbol || symbol == execSym) ? g_bufferPts : 0;
      double comm   = (symbol == _Symbol || symbol == execSym) ? g_commPerLot : 0.0;
      double oneRisk = 0.0;
      if(sl <= 0.0 || !EstimateStopRiskCash(symbol, isLong, volume, entry, sl, buffer, comm, oneRisk))
         known = false;
      else
         riskCash += oneRisk;
   }
   for(int j = OrdersTotal() - 1; j >= 0; j--)
   {
      ulong ticket = OrderGetTicket(j);
      if(ticket == 0) continue;
      string symbol = OrderGetString(ORDER_SYMBOL);
      long type     = OrderGetInteger(ORDER_TYPE);
      double sl     = OrderGetDouble(ORDER_SL);
      double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      double entry  = GetPendingOrderEffectiveEntry(ticket);
      int buffer    = (symbol == _Symbol || symbol == execSym) ? g_bufferPts : 0;
      double comm   = (symbol == _Symbol || symbol == execSym) ? g_commPerLot : 0.0;
      double oneRisk = 0.0;
      bool isLong   = IsBuyPendingType(type);
      bool stopOnLossSide = isLong ? (sl < entry) : (sl > entry);
      if(sl <= 0.0 || !stopOnLossSide || !EstimateStopRiskCash(symbol, isLong, volume, entry, sl, buffer, comm, oneRisk))
         known = false;
      else
         riskCash += oneRisk;
   }
   return known;
}

double GetRiskCashBudget(double riskShare, string &reason)
{
   reason = "";
   double budget = 0.0;
   if(!GetRiskCashBudgetForShare(riskShare, budget, reason))
      return 0.0;
   if(InpMaxPortfolioRiskPct > 0.0)
   {
      double eq = GetEffectiveEquity();
      double currentRisk = 0.0;
      if(!CalculateAccountExposureRisk(currentRisk))
      {
         reason = "Có vị thế/lệnh chờ chưa đặt SL; từ chối mở thêm để bảo vệ trần danh mục";
         return 0.0;
      }
      budget = MathMin(budget, eq * InpMaxPortfolioRiskPct / 100.0 - currentRisk);
   }
   if(budget <= 0.0)
   {
      reason = "Ngân sách rủi ro còn lại bằng 0 (Đã chạm trần rủi ro danh mục)";
      return 0.0;
   }
   return budget;
}

//+------------------------------------------------------------------+
//| Tính khối lượng vào lệnh an toàn không bao giờ vượt ngân sách    |
//+------------------------------------------------------------------+
bool CalculateSafeVolume(bool isBuy, double entry, double stop, double budgetCash, double &volume, double &riskAtMin)
{
   volume    = 0.0;
   riskAtMin = 0.0;
   if(entry <= 0.0 || stop <= 0.0 || budgetCash <= 0.0 || (isBuy && stop >= entry) || (!isBuy && stop <= entry))
      return false;

   string execSym = GetExecutionSymbol();
   double lossPerLot = 0.0;
   if(!EstimateStopRiskCash(execSym, isBuy, 1.0, entry, stop, g_bufferPts, g_commPerLot, lossPerLot) || lossPerLot <= 0.0)
      return false;

   double minLot = SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN);
   if(minLot <= 0.0)
      return false;

   riskAtMin = lossPerLot * minLot;
   if(riskAtMin > budgetCash + 0.01)
      return false;

   volume = FloorLotStep(MathMin(SymbolInfoDouble(execSym, SYMBOL_VOLUME_MAX), budgetCash / lossPerLot));
   if(volume < minLot)
      return false;

   if(lossPerLot * volume > budgetCash + MathMax(0.01, budgetCash * 0.000001))
   {
      double step = SymbolInfoDouble(execSym, SYMBOL_VOLUME_STEP);
      if(step <= 0.0) step = minLot;
      volume = FloorLotStep(volume - step);
   }
   return (volume >= minLot && lossPerLot * volume <= budgetCash + MathMax(0.01, budgetCash * 0.000001));
}

//+------------------------------------------------------------------+
//| Tính SL & TP chuẩn cho lệnh mới theo 5 chế độ nguồn SL           |
//+------------------------------------------------------------------+
bool GetEntryProtection(bool isBuy, double entry, double &sl, double &tp)
{
   string execSym = GetExecutionSymbol();
   double point = SymbolInfoDouble(execSym, SYMBOL_POINT);
   if(point <= 0.0)
      return false;

   double distance = 0.0;
   if(g_slMode == SL_MODE_POINTS)
      distance = MathMax(point, g_manualSlPts * point);
   else if(g_slMode == SL_MODE_FIXED_CASH)
   {
      double refLot = (g_enteredManualLot > 0.0) ? g_enteredManualLot : 1.0;
      double solvedDist = FindStopDistanceForRiskBudget(execSym, isBuy, entry, g_fixedCashSlBudget / MathMax(0.01, refLot), g_bufferPts, g_commPerLot);
      distance = (solvedDist > 0.0) ? solvedDist : MathMax(point, g_manualSlPts * point);
   }
   else if(g_slMode == SL_MODE_DRAG && g_sizerEntryPrice > 0.0 && g_sizerSlPrice > 0.0 &&
           ((isBuy && g_sizerSlPrice < g_sizerEntryPrice) || (!isBuy && g_sizerSlPrice > g_sizerEntryPrice)))
      distance = MathAbs(g_sizerEntryPrice - g_sizerSlPrice);
   else if(g_slMode == SL_MODE_ATR_LINE && g_pineTrailingStop > 0.0 &&
           ((isBuy && g_pineTrailingStop < entry) || (!isBuy && g_pineTrailingStop > entry)))
      distance = MathAbs(entry - g_pineTrailingStop);
   else if(g_pinnedSlDist > 0.0)
      distance = g_pinnedSlDist;
   else if(g_pineFirstBarSlDist > 0.0)
      distance = g_pineFirstBarSlDist;
   else if(g_pineLatestAtr > 0.0)
      distance = g_pineLatestAtr * MathMax(0.1, g_customValueForFirstDay);
   else
      distance = MathMax(point * MathMax(1, g_manualSlPts), 100.0 * point);

   long stops  = SymbolInfoInteger(execSym, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(execSym, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDistance = MathMax(point, (double)MathMax(stops, freeze) * point + point);
   distance = MathMax(distance, minDistance);

   double sign = isBuy ? 1.0 : -1.0;
   sl = NormalizePriceToTickSize(execSym, entry - sign * distance);
   tp = NormalizePriceToTickSize(execSym, entry + sign * distance * MathMax(0.1, g_targetRR));
   return (sl > 0.0 && tp > 0.0 && ((isBuy && sl < entry && tp > entry) || (!isBuy && sl > entry && tp < entry)));
}

//+------------------------------------------------------------------+
//| Lấy giá Entry Kế hoạch đã đóng băng của vị thế để đối chiếu trượt|
//+------------------------------------------------------------------+
double GetFrozenClosedEntryPrice(long positionId, datetime openTime, double actualEntry)
{
   if(positionId <= 0)
      return actualEntry;

   string gvKey = AccountScopedGV("EAP82_CLOSEPX_" + IntegerToString(positionId));
   if(GlobalVariableCheck(gvKey))
   {
      double savedPrice = GlobalVariableGet(gvKey);
      if(savedPrice > 0.0)
         return savedPrice;
   }

   double plannedPrice = 0.0;
   if(g_standbySetupLocked && g_standbyLockedEntry > 0.0 && MathAbs((double)(TimeCurrent() - openTime)) <= 300)
      plannedPrice = g_standbyLockedEntry;

   if(plannedPrice <= 0.0)
   {
      string gvTfKey = AccountScopedGV("EAP82_LOCKTF_" + IntegerToString(positionId));
      ENUM_TIMEFRAMES refTf = GlobalVariableCheck(gvTfKey) ? (ENUM_TIMEFRAMES)(int)GlobalVariableGet(gvTfKey)
                              : ((g_standbyLockedTf != PERIOD_CURRENT) ? g_standbyLockedTf : _Period);
      int entryShift = iBarShift(_Symbol, refTf, openTime, false);
      if(entryShift >= 0)
         plannedPrice = iClose(_Symbol, refTf, entryShift + 1);
      if(plannedPrice <= 0.0 && entryShift == 0)
         plannedPrice = iClose(_Symbol, refTf, 1);
   }
   if(plannedPrice <= 0.0)
      plannedPrice = actualEntry;

   if(plannedPrice > 0.0)
      GlobalVariableSet(gvKey, plannedPrice);
   return plannedPrice;
}

//+------------------------------------------------------------------+
//| Tính giá Hòa vốn Chung toàn rổ lệnh (Common BE: VWAP + Phí + Swap)|
//+------------------------------------------------------------------+
double CalculateCommonBreakEvenPrice(bool basketIsLong, int plusPoints = 0)
{
   string execSym = GetExecutionSymbol();
   double sumPV   = 0.0;
   double sumVol  = 0.0;
   double netSwap = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      string s = PositionGetString(POSITION_SYMBOL);
      if(s != _Symbol && s != execSym) continue;
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      if(isBuy != basketIsLong) continue;

      double v  = PositionGetDouble(POSITION_VOLUME);
      double px = PositionGetDouble(POSITION_PRICE_OPEN);
      sumVol   += v;
      sumPV    += px * v;
      netSwap  += PositionGetDouble(POSITION_SWAP);
   }
   if(sumVol <= 0.0)
      return 0.0;

   double vwap = sumPV / sumVol;
   double totalCostCash = MathMax(0.0, g_commPerLot) * sumVol - netSwap;
   double costPriceOffset = 0.0;

   if(totalCostCash > 0.0)
   {
      double point = SymbolInfoDouble(execSym, SYMBOL_POINT);
      double pnl100Pts = 0.0;
      ENUM_ORDER_TYPE oType = basketIsLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double testTarget = vwap + (basketIsLong ? 100.0 : -100.0) * point;
      if(point > 0.0 && OrderCalcProfit(oType, execSym, sumVol, vwap, testTarget, pnl100Pts) && pnl100Pts > 0.0)
      {
         double cashPerPoint = pnl100Pts / 100.0;
         costPriceOffset = (totalCostCash / cashPerPoint) * point;
      }
   }

   double sign = basketIsLong ? 1.0 : -1.0;
   double commonBe = vwap + sign * (costPriceOffset + MathMax(0, plusPoints) * ExecPoint());
   return NormalizePriceToTickSize(execSym, commonBe);
}

//+------------------------------------------------------------------+
//| Kiểm tra có cần gỡ Hard TP trên Broker để tránh xung đột Partial |
//+------------------------------------------------------------------+
bool ShouldSuppressBrokerHardTpForPartial(double positionVol, bool partialAlreadyDone,
                                          double currentEntry, double currentSL,
                                          double candidateTP, bool isLong)
{
   if(!InpPreventHardTpConflictWithPartial || !g_enPartial || partialAlreadyDone)
      return false;

   // Tìm tỷ lệ cắt nhỏ nhất đang bật trong ma trận 10 tầng TP
   double firstActivePct = g_partialPct;
   double firstActiveRR  = g_partialRR;
   for(int t = 0; t < 10; t++)
   {
      if(g_tpTiers[t].enabled && g_tpTiers[t].closePct < 100.0)
      {
         firstActivePct = g_tpTiers[t].closePct;
         if(g_tpTiers[t].triggerUnit == UNIT_RR)
            firstActiveRR = g_tpTiers[t].triggerVal;
         break;
      }
   }

   if(!CanSplitVolume(positionVol, firstActivePct))
      return false;

   bool trailOrBeActive = ((g_enTrail && g_trailStyle == TRAIL_STYLE_AUTO_ATR) ||
                           g_advTrailMode != ADV_TRAIL_OFF || g_enBe || g_enLock || InpEnableStepBreakEven);
   if(g_targetRR <= firstActiveRR + 0.05 && trailOrBeActive)
      return true;

   if(candidateTP > 0.0 && currentEntry > 0.0 && currentSL > 0.0)
   {
      double slDist = MathAbs(currentEntry - currentSL);
      double tpDist = isLong ? (candidateTP - currentEntry) : (currentEntry - candidateTP);
      if(slDist > _Point && tpDist > 0.0)
      {
         double candidateRR = tpDist / slDist;
         if(candidateRR <= firstActiveRR + 0.05 && trailOrBeActive)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Vẽ các đường ngang kéo thả Sizer (Entry, SL, TP, StopLimit, LPO) |
//+------------------------------------------------------------------+
void DrawSizerHLine(string name, double price, color clr, int width, ENUM_LINE_STYLE style, bool show)
{
   string obj = DRAG_PREFIX + name;
   if(!show || price <= 0.0)
   {
      ObjectDelete(0, obj);
      return;
   }
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, obj, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, obj, OBJPROP_STYLE, style);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, obj, OBJPROP_SELECTED, true);
      ObjectSetInteger(0, obj, OBJPROP_BACK, false);
   }
   ObjectSetDouble(0, obj, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
}

void DrawSizerZone(string name, datetime t1, datetime t2, double p1, double p2, color rawClr, bool show)
{
   string obj = DRAG_PREFIX + name;
   if(!show || p1 <= 0.0 || p2 <= 0.0 || p1 == p2)
   {
      ObjectDelete(0, obj);
      return;
   }
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, obj, OBJPROP_FILL, true);
      ObjectSetInteger(0, obj, OBJPROP_BACK, true);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   }
   color blended = BlendWithBg(rawClr, 14.0);
   ObjectSetInteger(0, obj, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, obj, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, obj, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, obj, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, blended);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, blended);
}

void DrawSizerTag(string name, datetime t, double price, string text, color clr, ENUM_ANCHOR_POINT anchor, bool show)
{
   string obj = DRAG_PREFIX + name;
   if(!show || price <= 0.0)
   {
      ObjectDelete(0, obj);
      return;
   }
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_TEXT, 0, t, price);
      ObjectSetString(0, obj, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, obj, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, obj, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, obj, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
//| Bộ máy Định cỡ Trung tâm: Tính Lot, Chia 3 nhịp & Vẽ Sizer/BE    |
//+------------------------------------------------------------------+
void CalculateSizingAndActiveRules(int openOrderCount,
                                   double openTotalVol,
                                   double openVwapEntry,
                                   double openActiveSL,
                                   double openActiveTP,
                                   bool openIsLong,
                                   long anchorId,
                                   datetime earliestOpenTime,
                                   double &outSlPriceDist,
                                   double &outSlPoints,
                                   double &outRecommendedLot,
                                   double &outDisplayVol,
                                   double &outDisplayRiskCash,
                                   double &outDisplayRiskPct,
                                   bool &outRiskKnown,
                                   double &outDisplayRewardCash,
                                   double &outPartialLot,
                                   double &outRemainLot)
{
   outSlPriceDist       = 0.0;
   outSlPoints          = 0.0;
   outRecommendedLot    = 0.0;
   outDisplayVol        = 0.0;
   outDisplayRiskCash   = 0.0;
   outDisplayRiskPct    = 0.0;
   outRiskKnown         = true;
   outDisplayRewardCash = 0.0;
   outPartialLot        = 0.0;
   outRemainLot         = 0.0;

   string execSym = GetExecutionSymbol();
   double bid = SymbolInfoDouble(execSym, SYMBOL_BID);
   double ask = SymbolInfoDouble(execSym, SYMBOL_ASK);

   int pendingCount = 0;
   double pendingEntry = 0.0, pendingSL = 0.0, pendingTP = 0.0, pendingVol = 0.0;
   bool pendingIsLong = true;
   datetime pendingTime = 0;
   if(openOrderCount == 0)
   {
      for(int j = OrdersTotal() - 1; j >= 0; j--)
      {
         ulong ordTk = OrderGetTicket(j);
         if(ordTk > 0)
         {
            string oSym = OrderGetString(ORDER_SYMBOL);
            if(oSym == _Symbol || oSym == execSym)
            {
               pendingCount++;
               pendingEntry = GetPendingOrderEffectiveEntry(ordTk);
               pendingSL    = OrderGetDouble(ORDER_SL);
               pendingTP    = OrderGetDouble(ORDER_TP);
               pendingVol  += OrderGetDouble(ORDER_VOLUME_CURRENT);
               pendingTime  = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
               long oType   = OrderGetInteger(ORDER_TYPE);
               pendingIsLong= IsBuyPendingType(oType);
            }
         }
      }
   }

   bool isLong = (openOrderCount > 0) ? openIsLong : ((pendingCount > 0) ? pendingIsLong : (g_tradeSide == SIDE_LONG));
   ENUM_TIMEFRAMES setupTf = (g_resolvedAtrTf != PERIOD_CURRENT) ? g_resolvedAtrTf : _Period;
   double live = iClose(_Symbol, setupTf, 1);
   if(live <= 0.0)
      live = isLong ? (ask > 0.0 ? ask : bid) : (bid > 0.0 ? bid : ask);

   double atrValue = (g_pineLatestAtr > 0.0) ? g_pineLatestAtr : (100 * _Point);
   double sign     = isLong ? 1.0 : -1.0;

   double equity = GetEffectiveEquity();
   double riskBudgetCash = 0.0;
   string riskBudgetReason = "";
   if(!GetRiskCashBudgetForShare(1.0, riskBudgetCash, riskBudgetReason))
   {
      riskBudgetCash = 0.0;
      outRiskKnown   = false;
   }
   double activeRiskPct = (equity > 0.0 && riskBudgetCash > 0.0)
                          ? (riskBudgetCash / equity * 100.0) : 0.0;

   double techSlDist = (g_pineFirstBarSlDist > 0.0) ? g_pineFirstBarSlDist : (atrValue * g_customValueForFirstDay);
   if(g_slMode == SL_MODE_ATR_LINE && g_pineTrailingStop > 0.0 && !g_pineStopPlotting)
   {
      double refEntry = (openOrderCount > 0) ? openVwapEntry : (g_pinSizerEntry && g_sizerEntryPrice > 0.0 ? g_sizerEntryPrice : live);
      double distLine = MathAbs(refEntry - g_pineTrailingStop);
      if(distLine > 0.0)
         techSlDist = distLine;
   }
   else if(g_slMode == SL_MODE_POINTS)
      techSlDist = g_manualSlPts * _Point;
   else if(g_slMode == SL_MODE_FIXED_CASH)
   {
      double refEntry = (openOrderCount > 0) ? openVwapEntry : (g_sizerEntryPrice > 0.0 ? g_sizerEntryPrice : live);
      double refLot   = (openOrderCount > 0 && openTotalVol > 0.0) ? openTotalVol : ((g_enteredManualLot > 0.0) ? g_enteredManualLot : 1.0);
      double solved   = FindStopDistanceForRiskBudget(execSym, isLong, refEntry, g_fixedCashSlBudget / MathMax(0.01, refLot), g_bufferPts, g_commPerLot);
      if(solved > 0.0)
         techSlDist = solved;
   }
   else if(g_slMode == SL_MODE_DRAG && g_sizerEntryPrice > 0.0 && g_sizerSlPrice > 0.0)
      techSlDist = MathAbs(g_sizerEntryPrice - g_sizerSlPrice);

   if(techSlDist <= 0.0)
      techSlDist = atrValue * g_customValueForFirstDay;

   if(openOrderCount > 0 && openTotalVol > 0.0)
   {
      g_actualFillEntryPrice = NormalizeDouble(openVwapEntry, _Digits);
      g_sizerEntryPrice      = g_actualFillEntryPrice;
      if(g_plannedEntryPrice <= 0.0)
         g_plannedEntryPrice = (g_standbyLockedEntry > 0.0) ? g_standbyLockedEntry : g_actualFillEntryPrice;
      outDisplayVol = openTotalVol;

      string gvLock1R = AccountScopedGV("EAP82_LK1R_" + IntegerToString(anchorId));
      string gvLockSL = AccountScopedGV("EAP82_LKSL_" + IntegerToString(anchorId));
      string gvLockTP = AccountScopedGV("EAP82_LKTP_" + IntegerToString(anchorId));
      string gvLockVl = AccountScopedGV("EAP82_LKVL_" + IntegerToString(anchorId));

      double savedVol = GlobalVariableCheck(gvLockVl) ? GlobalVariableGet(gvLockVl) : 0.0;
      double locked1R = GlobalVariableCheck(gvLock1R) ? GlobalVariableGet(gvLock1R) : 0.0;
      double lockedSL = GlobalVariableCheck(gvLockSL) ? GlobalVariableGet(gvLockSL) : 0.0;
      double lockedTP = GlobalVariableCheck(gvLockTP) ? GlobalVariableGet(gvLockTP) : 0.0;

      bool slStillInRiskZone = (openActiveSL > 0.0) &&
                               ((isLong && openActiveSL < openVwapEntry - _Point) ||
                                (!isLong && openActiveSL > openVwapEntry + _Point));

      if(locked1R <= 0.0 || openTotalVol > savedVol + 1e-5 || (slStillInRiskZone && !g_isTrailingArmedNow))
      {
         if(slStillInRiskZone)
         {
            locked1R = MathAbs(openVwapEntry - openActiveSL);
         }
         else if(g_volRule == RULE_SCALE_DIST_BY_VOL)
         {
            double budgetPerLot   = riskBudgetCash / openTotalVol;
            double scaledDistance = FindStopDistanceForRiskBudget(execSym, isLong, openVwapEntry,
                                                                  budgetPerLot, g_bufferPts, g_commPerLot);
            locked1R = (scaledDistance > 0.0) ? scaledDistance : techSlDist;
            if(scaledDistance <= 0.0)
               AlertThrottled("RISK_SCALE_UNAVAILABLE", "Không thể giải ngược SL theo Risk/Vol; giữ nguyên khoảng SL đang chọn.");
         }
         else
         {
            locked1R = techSlDist;
         }
         lockedSL = (openActiveSL > 0.0) ? openActiveSL : NormalizeDouble(g_sizerEntryPrice - sign * locked1R, _Digits);
         lockedTP = (openActiveTP > 0.0) ? openActiveTP : NormalizeDouble(g_sizerEntryPrice + sign * locked1R * g_targetRR, _Digits);

         GlobalVariableSet(gvLock1R, locked1R);
         GlobalVariableSet(gvLockSL, lockedSL);
         GlobalVariableSet(gvLockTP, lockedTP);
         GlobalVariableSet(gvLockVl, openTotalVol);
      }

      double actualSlDistFromFill = (openActiveSL > 0.0) ? MathAbs(g_sizerEntryPrice - openActiveSL) : locked1R;
      outSlPriceDist = (actualSlDistFromFill > 0.0) ? actualSlDistFromFill : locked1R;
      g_sizerSlPrice = (openActiveSL > 0.0) ? NormalizeDouble(openActiveSL, _Digits) : NormalizeDouble(lockedSL, _Digits);
      double visualTargetTp = NormalizeDouble(g_sizerEntryPrice + sign * outSlPriceDist * g_targetRR, _Digits);
      g_sizerTpPrice = (openActiveTP > 0.0) ? NormalizeDouble(openActiveTP, _Digits)
                       : ((lockedTP > 0.0 && !g_hardTpSuppressedForPartial) ? NormalizeDouble(lockedTP, _Digits) : visualTargetTp);
   }
   else if(pendingCount > 0 && pendingEntry > 0.0)
   {
      g_plannedEntryPrice    = NormalizeDouble(pendingEntry, _Digits);
      g_actualFillEntryPrice = 0.0;
      g_sizerEntryPrice      = g_plannedEntryPrice;
      outSlPriceDist         = (pendingSL > 0.0) ? MathAbs(pendingEntry - pendingSL) : techSlDist;
      g_sizerSlPrice         = (pendingSL > 0.0) ? NormalizeDouble(pendingSL, _Digits) : NormalizeDouble(g_sizerEntryPrice - sign * outSlPriceDist, _Digits);
      g_sizerTpPrice         = (pendingTP > 0.0) ? NormalizeDouble(pendingTP, _Digits) : NormalizeDouble(g_sizerEntryPrice + sign * outSlPriceDist * g_targetRR, _Digits);
      outDisplayVol          = pendingVol;
   }
   else
   {
      g_actualFillEntryPrice = 0.0;
      if(g_slMode == SL_MODE_DRAG)
      {
         if(g_sizerEntryPrice <= 0.0)
            g_sizerEntryPrice = NormalizeDouble(live, _Digits);
         if(g_sizerSlPrice <= 0.0)
            g_sizerSlPrice = NormalizeDouble(g_sizerEntryPrice - sign * techSlDist, _Digits);

         outSlPriceDist = MathAbs(g_sizerEntryPrice - g_sizerSlPrice);
         bool dragBuy   = (g_sizerEntryPrice >= g_sizerSlPrice);
         g_tradeSide    = dragBuy ? SIDE_LONG : SIDE_SHORT;
         g_sizerTpPrice = dragBuy ? NormalizeDouble(g_sizerEntryPrice + outSlPriceDist * g_targetRR, _Digits)
                                  : NormalizeDouble(g_sizerEntryPrice - outSlPriceDist * g_targetRR, _Digits);
         g_plannedEntryPrice = g_sizerEntryPrice;
         if(InpLockStandbySetupTfAndBar)
         {
            g_standbyLockedEntry = g_sizerEntryPrice;
            g_standbyLockedSl    = g_sizerSlPrice;
            g_standbyLockedTp    = g_sizerTpPrice;
            g_standbyLocked1R    = outSlPriceDist;
            g_standbySetupLocked = true;
            SaveStandbySetupToGV();
         }
      }
      else if(g_pinSizerEntry && g_sizerEntryPrice > 0.0)
      {
         outSlPriceDist      = (g_pinnedSlDist > 0.0) ? g_pinnedSlDist : techSlDist;
         g_sizerSlPrice      = NormalizeDouble(g_sizerEntryPrice - sign * outSlPriceDist, _Digits);
         g_sizerTpPrice      = NormalizeDouble(g_sizerEntryPrice + sign * outSlPriceDist * g_targetRR, _Digits);
         g_plannedEntryPrice = g_sizerEntryPrice;
      }
      else if(InpLockStandbySetupTfAndBar && g_standbySetupLocked && g_standbyLockedEntry > 0.0 && g_standbyLocked1R > 0.0)
      {
         g_sizerEntryPrice   = NormalizeDouble(g_standbyLockedEntry, _Digits);
         outSlPriceDist      = g_standbyLocked1R;
         g_pinnedSlDist      = g_standbyLocked1R;
         g_sizerSlPrice      = NormalizeDouble(g_standbyLockedSl, _Digits);
         g_sizerTpPrice      = NormalizeDouble(g_standbyLockedTp, _Digits);
         g_plannedEntryPrice = g_sizerEntryPrice;
      }
      else
      {
         g_sizerEntryPrice = NormalizeDouble(live, _Digits);
         outSlPriceDist    = techSlDist;
         g_pinnedSlDist    = techSlDist;
         g_sizerSlPrice    = (g_slMode == SL_MODE_ATR_LINE && g_pineTrailingStop > 0.0 && !g_pineStopPlotting)
                             ? NormalizeDouble(g_pineTrailingStop, _Digits)
                             : NormalizeDouble(g_sizerEntryPrice - sign * outSlPriceDist, _Digits);
         outSlPriceDist      = MathAbs(g_sizerEntryPrice - g_sizerSlPrice);
         g_sizerTpPrice      = NormalizeDouble(g_sizerEntryPrice + sign * outSlPriceDist * g_targetRR, _Digits);
         g_plannedEntryPrice = g_sizerEntryPrice;

         if(InpLockStandbySetupTfAndBar && g_sizerEntryPrice > 0.0 && outSlPriceDist > 0.0)
         {
            g_standbyLockedTf         = setupTf;
            g_standbyLockedRefBarTime = iTime(_Symbol, setupTf, 1);
            g_standbyLockedEntry      = g_sizerEntryPrice;
            g_standbyLockedSl         = g_sizerSlPrice;
            g_standbyLockedTp         = g_sizerTpPrice;
            g_standbyLocked1R         = outSlPriceDist;
            g_standbySetupLocked      = true;
            SaveStandbySetupToGV();
         }
      }
   }

   // Đồng bộ mức giá phụ cho lệnh Buy/Sell Stop Limit
   if(g_entryMode == ENTRY_MODE_STOP_LIMIT)
   {
      if(g_sizerStopLimitPrice <= 0.0 ||
         (isLong && g_sizerStopLimitPrice > g_sizerEntryPrice) ||
         (!isLong && g_sizerStopLimitPrice < g_sizerEntryPrice))
      {
         g_sizerStopLimitPrice = NormalizePriceToTickSize(execSym, g_sizerEntryPrice - sign * g_stopLimitOffsetPts * _Point);
      }
   }

   double effectiveSizingEntry = (g_entryMode == ENTRY_MODE_STOP_LIMIT && openOrderCount == 0 && g_sizerStopLimitPrice > 0.0)
                                 ? g_sizerStopLimitPrice : g_sizerEntryPrice;

   // Nếu người dùng chọn chế độ Partial SL gia quyền (WEIGHTED_BUDGET), tính hệ số thu hẹp khoảng SL hiệu dụng
   double slWeightFactor = 1.0;
   if(g_enPartialSL && InpPartialSlMode == PARTIAL_SL_WEIGHTED_BUDGET)
   {
      double sumPct = 0.0, weightedSum = 0.0;
      for(int s = 0; s < 10; s++)
      {
         if(g_slTiers[s].enabled && g_slTiers[s].triggerUnit == UNIT_RR && g_slTiers[s].triggerVal > 0.0 && g_slTiers[s].triggerVal <= 1.0)
         {
            double p = MathMin(100.0 - sumPct, g_slTiers[s].closePct);
            if(p > 0.0)
            {
               weightedSum += (p / 100.0) * g_slTiers[s].triggerVal;
               sumPct      += p;
            }
         }
      }
      if(sumPct > 0.0)
      {
         weightedSum += ((100.0 - sumPct) / 100.0) * 1.0;
         slWeightFactor = MathMax(0.25, MathMin(1.0, weightedSum));
      }
   }

   double currentSlGap    = MathAbs(effectiveSizingEntry - g_sizerSlPrice);
   outSlPoints            = (_Point > 0.0) ? (currentSlGap / _Point) : 0.0;
   double tpDistancePrice = MathAbs(g_sizerTpPrice - effectiveSizingEntry);
   double actualRR        = (currentSlGap > 0.0) ? (tpDistancePrice / currentSlGap) : g_targetRR;

   // Nếu bật Virtual SL và người dùng chọn định cỡ theo Emergency Server SL, nhân khoảng cách SL khi tính lot
   double sizingStopPrice = g_sizerSlPrice;
   if(g_virtualSLOn && InpVirtualSlSizingBasis == VSL_SIZE_BY_EMERGENCY_STOP && openOrderCount == 0)
   {
      double emgMult = MathMax(1.05, InpEmergencySLMultiplier);
      sizingStopPrice = NormalizePriceToTickSize(execSym, effectiveSizingEntry - sign * currentSlGap * emgMult);
   }

   double riskOneLot = 0.0;
   bool stopOnLossSide = isLong ? (sizingStopPrice < effectiveSizingEntry) : (sizingStopPrice > effectiveSizingEntry);
   bool oneLotRiskKnown = stopOnLossSide && EstimateStopRiskCash(execSym, isLong, 1.0, effectiveSizingEntry,
                                                                 sizingStopPrice, g_bufferPts, g_commPerLot, riskOneLot);
   riskOneLot *= slWeightFactor;

   double totalSetupBudget = riskBudgetCash;
   if(InpMaxPortfolioRiskPct > 0.0)
   {
      double portfolioRisk = 0.0;
      if(!CalculateAccountExposureRisk(portfolioRisk))
      {
         totalSetupBudget = 0.0;
         outRiskKnown     = false;
      }
      else if(openOrderCount == 0 && pendingCount == 0)
      {
         totalSetupBudget = MathMin(totalSetupBudget,
                                    MathMax(0.0, equity * (InpMaxPortfolioRiskPct / 100.0) - portfolioRisk));
      }
   }

   double currentSymbolRiskCash = 0.0, currentSymbolVol = 0.0;
   bool symbolExposureKnown = true;
   if(openOrderCount > 0 || pendingCount > 0)
      symbolExposureKnown = CalculateChartSymbolExposureRisk(currentSymbolRiskCash, currentSymbolVol, true);

   g_remainingSetupRiskCash = MathMax(0.0, totalSetupBudget - (symbolExposureKnown ? currentSymbolRiskCash : totalSetupBudget));
   g_remainingSetupRiskPct  = (equity > 0.0) ? (g_remainingSetupRiskCash / equity * 100.0) : 0.0;

   double s1 = MathMax(0.0, InpLeg1RiskSharePct);
   double s2 = MathMax(0.0, InpLeg2RiskSharePct);
   double s3 = MathMax(0.0, InpLeg3RiskSharePct);
   double sumShares = s1 + s2 + s3;
   if(sumShares <= 0.0) { s1 = 100.0; s2 = 0.0; s3 = 0.0; sumShares = 100.0; }
   double w1 = s1 / sumShares;
   double w2 = s2 / sumShares;
   double w3 = s3 / sumShares;

   if(oneLotRiskKnown && riskOneLot > 0.0 && totalSetupBudget > 0.0)
   {
      outRecommendedLot  = FloorLotStep(totalSetupBudget / riskOneLot);
      g_leg1SuggestedLot = FloorLotStep((totalSetupBudget * w1) / riskOneLot);
      g_leg2SuggestedLot = FloorLotStep((totalSetupBudget * w2) / riskOneLot);
      g_leg3SuggestedLot = FloorLotStep((totalSetupBudget * w3) / riskOneLot);

      int activeOrderLegs = openOrderCount + pendingCount;
      if(InpSplitSetupRiskAcrossOrders)
      {
         double nextLegTargetCash = 0.0;
         if(activeOrderLegs == 0)
            nextLegTargetCash = totalSetupBudget * w1;
         else if(activeOrderLegs == 1)
            nextLegTargetCash = MathMin(g_remainingSetupRiskCash, totalSetupBudget * w2);
         else
            nextLegTargetCash = g_remainingSetupRiskCash;
         g_nextAddOnSuggestedLot = (nextLegTargetCash > 0.0) ? FloorLotStep(nextLegTargetCash / riskOneLot) : 0.0;
      }
      else
      {
         g_nextAddOnSuggestedLot = (g_remainingSetupRiskCash > 0.0) ? FloorLotStep(g_remainingSetupRiskCash / riskOneLot) : 0.0;
      }

      if(openOrderCount == 0 && pendingCount == 0)
         outDisplayVol = (g_enteredManualLot > 0.0) ? FloorLotStep(g_enteredManualLot) : outRecommendedLot;
   }
   else
   {
      outRiskKnown            = false;
      outRecommendedLot       = 0.0;
      g_leg1SuggestedLot      = 0.0;
      g_leg2SuggestedLot      = 0.0;
      g_leg3SuggestedLot      = 0.0;
      g_nextAddOnSuggestedLot = 0.0;
      if(openOrderCount == 0 && pendingCount == 0)
         outDisplayVol = (g_enteredManualLot > 0.0) ? FloorLotStep(g_enteredManualLot) : 0.0;
   }

   if(openOrderCount > 0 || pendingCount > 0)
   {
      double exposureRisk = 0.0, exposureVol = 0.0;
      outRiskKnown       = CalculateChartSymbolExposureRisk(exposureRisk, exposureVol, openOrderCount == 0);
      outDisplayRiskCash = outRiskKnown ? exposureRisk : 0.0;
      outDisplayVol      = exposureVol;
   }
   else
      outDisplayRiskCash = outRiskKnown ? riskOneLot * outDisplayVol : 0.0;

   outDisplayRiskPct = (outRiskKnown && equity > 0.0) ? (outDisplayRiskCash / equity * 100.0) : 0.0;

   double pnlAtTarget = 0.0;
   if(outDisplayVol > 0.0 && OrderCalcProfit(isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                                             execSym, outDisplayVol, effectiveSizingEntry, g_sizerTpPrice, pnlAtTarget))
      outDisplayRewardCash = MathMax(0.0, pnlAtTarget - MathMax(0.0, g_commPerLot) * outDisplayVol);
   else
      outDisplayRewardCash = 0.0;

   double minL = SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN);
   if(outDisplayVol > 0.0 && g_enPartial)
   {
      double pLot = FloorLotStep(outDisplayVol * (g_partialPct / 100.0));
      if(pLot >= minL && (outDisplayVol - pLot) >= minL - 1e-6)
      {
         outPartialLot = pLot;
         outRemainLot  = NormalizeDouble(outDisplayVol - pLot, GetStepDigits(SymbolInfoDouble(execSym, SYMBOL_VOLUME_STEP)));
      }
      else
      {
         outPartialLot = 0.0;
         outRemainLot  = outDisplayVol;
      }
   }
   else
   {
      outPartialLot = 0.0;
      outRemainLot  = outDisplayVol;
   }

   // =========================================================================
   // VẼ ĐƯỜNG SIZER, ĐƯỜNG STOP-LIMIT, COMMON BE & VÙNG RỦI RO TRÊN BIỂU ĐỒ
   // =========================================================================
   datetime tRight = TimeCurrent();
   datetime tLeft  = tRight - 86400;

   if(openOrderCount > 0 && earliestOpenTime > 0)
      tLeft = earliestOpenTime;
   else if(pendingCount > 0 && pendingTime > 0)
      tLeft = pendingTime;
   else if(InpLockStandbySetupTfAndBar && g_standbySetupLocked && g_standbyLockedRefBarTime > 0)
      tLeft = g_standbyLockedRefBarTime;

   DrawSizerHLine("ENTRY", g_sizerEntryPrice, C_BTN_BUY, 2, STYLE_SOLID, g_showSizer);
   DrawSizerHLine("SL",    g_sizerSlPrice,    clrRed,    2, STYLE_SOLID, g_showSizer);
   DrawSizerHLine("TP",    g_sizerTpPrice,    clrLimeGreen, 2, STYLE_DASH, g_showSizer);

   // Vẽ đường phụ STOPLIMIT_PRICE khi đang chọn kiểu lệnh Buy/Sell Stop Limit
   bool showStopLimitLine = (g_showSizer && openOrderCount == 0 && g_entryMode == ENTRY_MODE_STOP_LIMIT);
   DrawSizerHLine("STOPLIMIT", g_sizerStopLimitPrice, clrGold, 2, STYLE_DASHDOT, showStopLimitLine);
   DrawSizerTag("T_STOPLIMIT", tRight, g_sizerStopLimitPrice,
                StringFormat("STOP-LIMIT EXEC %s (Offset: %d pts) ", DoubleToString(g_sizerStopLimitPrice, _Digits), g_stopLimitOffsetPts),
                clrGold, ANCHOR_RIGHT_UPPER, showStopLimitLine);

   // Tính và vẽ đường Hòa vốn chung toàn rổ lệnh (Common Break Even)
   g_commonBePrice = (openOrderCount > 0 && g_enCommonBe) ? CalculateCommonBreakEvenPrice(isLong, g_bePoints) : 0.0;
   string commonBeObj = VIS_PREFIX + "COMMON_BE";
   if(g_showSizer && openOrderCount > 1 && g_enCommonBe && g_commonBePrice > 0.0)
   {
      if(ObjectFind(0, commonBeObj) < 0)
      {
         ObjectCreate(0, commonBeObj, OBJ_HLINE, 0, 0, g_commonBePrice);
         ObjectSetInteger(0, commonBeObj, OBJPROP_COLOR, clrGold);
         ObjectSetInteger(0, commonBeObj, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, commonBeObj, OBJPROP_STYLE, STYLE_DASHDOTDOT);
         ObjectSetInteger(0, commonBeObj, OBJPROP_SELECTABLE, false);
      }
      ObjectSetDouble(0, commonBeObj, OBJPROP_PRICE, 0, g_commonBePrice);
      ObjectSetString(0, commonBeObj, OBJPROP_TEXT, "Common BE (VWAP + Fee/Swap): " + DoubleToString(g_commonBePrice, _Digits));
   }
   else
      ObjectDelete(0, commonBeObj);

   // Vẽ đường tham chiếu "Entry kế hoạch" khi lệnh khớp bị trượt giá so với kế hoạch
   bool showPlannedRefLine = (g_showSizer && openOrderCount > 0 && g_plannedEntryPrice > 0.0 &&
                              MathAbs(g_plannedEntryPrice - g_sizerEntryPrice) >= _Point);
   string planLineObj = DRAG_PREFIX + "PLAN_ENTRY";
   if(showPlannedRefLine)
   {
      if(ObjectFind(0, planLineObj) < 0)
      {
         ObjectCreate(0, planLineObj, OBJ_HLINE, 0, 0, g_plannedEntryPrice);
         ObjectSetInteger(0, planLineObj, OBJPROP_COLOR, clrSilver);
         ObjectSetInteger(0, planLineObj, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, planLineObj, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, planLineObj, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, planLineObj, OBJPROP_BACK, true);
      }
      ObjectSetDouble(0, planLineObj, OBJPROP_PRICE, 0, g_plannedEntryPrice);
   }
   else
      ObjectDelete(0, planLineObj);

   DrawSizerZone("Z_RISK",   tLeft, tRight, effectiveSizingEntry, g_sizerSlPrice, clrRed,       g_showSizer);
   DrawSizerZone("Z_REWARD", tLeft, tRight, effectiveSizingEntry, g_sizerTpPrice, clrLimeGreen, g_showSizer);

   string tfLockStr  = GetTfShortName(g_resolvedAtrTf);
   double entryDiffPts = (openOrderCount > 0 && g_plannedEntryPrice > 0.0 && _Point > 0.0)
                         ? ((g_sizerEntryPrice - g_plannedEntryPrice) / _Point) : 0.0;

   string entryTagTxt = "";
   if(openOrderCount > 0)
   {
      entryTagTxt = StringFormat("GIÁ KHỚP THỰC TẾ (%d lệnh | %s): %s [Entry KH: %s | Lệch: %+.0f pts] | MỞ: %.2f LOT (Gợi ý: %.2f) ",
                                 openOrderCount, tfLockStr, DoubleToString(g_sizerEntryPrice, _Digits),
                                 DoubleToString(g_plannedEntryPrice, _Digits), entryDiffPts, outDisplayVol, outRecommendedLot);
   }
   else if(InpSplitSetupRiskAcrossOrders && (w1 < 0.999))
   {
      entryTagTxt = StringFormat("ENTRY KẾ HOẠCH %s (Khung %s) | TỔNG: %.2f LOT (%.2f%%) [L1: %.2f | L2: %.2f | L3: %.2f] ",
                                 DoubleToString(g_sizerEntryPrice, _Digits), tfLockStr, outRecommendedLot, activeRiskPct,
                                 g_leg1SuggestedLot, g_leg2SuggestedLot, g_leg3SuggestedLot);
   }
   else
   {
      entryTagTxt = StringFormat("ENTRY KẾ HOẠCH %s (Khung %s) | GỢI Ý: %.2f LOT (Risk %.2f%%) ",
                                 DoubleToString(g_sizerEntryPrice, _Digits), tfLockStr, outRecommendedLot, activeRiskPct);
   }

   string riskTag = "";
   if(openOrderCount > 0)
   {
      riskTag = outRiskKnown
                ? StringFormat("Risk thực tế (%.2f Lot): -$%.2f (%.2f%% / Mục tiêu %.2f%%)", outDisplayVol, outDisplayRiskCash, outDisplayRiskPct, activeRiskPct)
                : "Risk chưa xác định (kiểm tra SL / dữ liệu broker)";
   }
   else
   {
      riskTag = outRiskKnown
                ? StringFormat("Risk dự kiến (%.2f Lot): -$%.2f (%.2f%%)", outDisplayVol, outDisplayRiskCash, outDisplayRiskPct)
                : "Risk chưa xác định (kiểm tra SL / dữ liệu broker)";
   }
   string slTagTxt = StringFormat("STOP LOSS %s (%.0f pts) | %s ",
                                  DoubleToString(g_sizerSlPrice, _Digits), outSlPoints, riskTag);

   string tpModeNote = (openOrderCount > 0 && g_hardTpSuppressedForPartial)
                       ? StringFormat("TP1/%.0f%%", g_partialPct) : "TP";
   string tpTagTxt   = StringFormat("%s +%.2f %s | %.2fR @ %s ",
                                    tpModeNote, outDisplayRewardCash, AccountInfoString(ACCOUNT_CURRENCY),
                                    actualRR, DoubleToString(g_sizerTpPrice, _Digits));

   DrawSizerTag("T_ENTRY", tRight, g_sizerEntryPrice, entryTagTxt, C_BTN_BUY, ANCHOR_RIGHT_LOWER, g_showSizer);
   DrawSizerTag("T_SL",    tRight, g_sizerSlPrice,    slTagTxt,    clrTomato, ANCHOR_RIGHT_LOWER, g_showSizer);
   DrawSizerTag("T_TP",    tRight, g_sizerTpPrice,    tpTagTxt,    clrLime,   ANCHOR_RIGHT_LOWER, g_showSizer);
}
// ============================================================================
// MODULE 3: CAnchoredAtrEngine (PINE RMA ATR, BAR-OPEN CACHE & SPOTLIGHT 3 TẦNG)
// ============================================================================

//+------------------------------------------------------------------+
//| Tự động dò khung thời gian có khoảng ATR*FirstMul khớp SL nhất   |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES DetectBestMatchingTimeframeForSlDist(double actualSlDist)
{
   if(actualSlDist <= 0.0)
      return _Period;

   ENUM_TIMEFRAMES candidates[6] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1};
   ENUM_TIMEFRAMES bestTf = PERIOD_H1;
   double minDiff = 1e18;

   for(int idx = 0; idx < 6; idx++)
   {
      MqlRates r[];
      ArraySetAsSeries(r, false);
      int copied = CopyRates(_Symbol, candidates[idx], 0, g_atrLength * 3 + 10, r);
      if(copied <= 2)
         continue;

      double sumTR = 0.0;
      double atr   = 0.0;
      int len      = MathMax(1, g_atrLength);
      for(int i = 0; i < copied - 1; i++)
      {
         double tr = r[i].high - r[i].low;
         if(i > 0)
         {
            double hc = MathAbs(r[i].high - r[i - 1].close);
            double lc = MathAbs(r[i].low  - r[i - 1].close);
            if(hc > tr) tr = hc;
            if(lc > tr) tr = lc;
         }
         if(i < len) { sumTR += tr; atr = sumTR / (double)(i + 1); }
         else        { atr = (atr * (double)(len - 1) + tr) / (double)len; }
      }

      double expectedSlDist = atr * g_customValueForFirstDay;
      double diff = MathAbs(expectedSlDist - actualSlDist);
      if(diff < minDiff)
      {
         minDiff = diff;
         bestTf  = candidates[idx];
      }
   }
   return bestTf;
}

//+------------------------------------------------------------------+
//| Xác định và khóa cứng khung thời gian ATR cho vị thế / Setup     |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES ResolveActiveAtrTimeframe(int openOrderCount, long anchorPosId, datetime earliestOpenTime, double actualSlDist)
{
   if(openOrderCount > 0 && anchorPosId > 0)
   {
      string gvTfKey   = AccountScopedGV("EAP82_LOCKTF_" + IntegerToString(anchorPosId));
      string gvTfExact = AccountScopedGV("EAP82_EXACT_"  + IntegerToString(anchorPosId));

      // Khóa cứng khung thời gian riêng cho từng vị thế/rổ lệnh đang mở. Đổi khung biểu đồ không được ghi đè.
      if(GlobalVariableCheck(gvTfKey))
      {
         int savedTf = (int)GlobalVariableGet(gvTfKey);
         if(savedTf > 0)
            return (ENUM_TIMEFRAMES)savedTf;
      }

      ENUM_TIMEFRAMES selectedTf = (g_standbySetupLocked && g_standbyLockedTf != PERIOD_CURRENT) ? g_standbyLockedTf : _Period;
      if(g_atrTfMode == ATR_TF_FIXED_H1)       selectedTf = PERIOD_H1;
      else if(g_atrTfMode == ATR_TF_FIXED_M15) selectedTf = PERIOD_M15;
      else if(g_atrTfMode == ATR_TF_FIXED_M5)  selectedTf = PERIOD_M5;
      else if(g_atrTfMode == ATR_TF_FIXED_H4)  selectedTf = PERIOD_H4;
      else if(g_atrTfMode == ATR_TF_FIXED_D1)  selectedTf = PERIOD_D1;
      else if(g_atrTfMode == ATR_TF_AUTO_ENTRY && !g_standbySetupLocked && (TimeCurrent() - earliestOpenTime) > 120)
      {
         if(_Period == PERIOD_H1 || _Period == PERIOD_H4 || _Period == PERIOD_D1)
            selectedTf = _Period;
         else
            selectedTf = DetectBestMatchingTimeframeForSlDist(actualSlDist);
      }

      GlobalVariableSet(gvTfKey,   (double)selectedTf);
      GlobalVariableSet(gvTfExact, 1.0);
      return selectedTf;
   }

   if(g_atrTfMode == ATR_TF_FIXED_H1)  return PERIOD_H1;
   if(g_atrTfMode == ATR_TF_FIXED_M15) return PERIOD_M15;
   if(g_atrTfMode == ATR_TF_FIXED_M5)  return PERIOD_M5;
   if(g_atrTfMode == ATR_TF_FIXED_H4)  return PERIOD_H4;
   if(g_atrTfMode == ATR_TF_FIXED_D1)  return PERIOD_D1;

   // Lúc chờ lệnh: nếu bật khóa khung cho setup thì giữ nguyên khung đã khóa khi người dùng chuyển đổi khung biểu đồ
   if(InpLockStandbySetupTfAndBar)
   {
      if(!g_standbySetupLocked)
         LoadStandbySetupFromGV();
      if(g_standbySetupLocked && g_standbyLockedTf != PERIOD_CURRENT)
         return g_standbyLockedTf;
      if(g_standbyLockedTf != PERIOD_CURRENT)
         return g_standbyLockedTf;
   }
   return _Period;
}

//+------------------------------------------------------------------+
//| Các hàm vẽ đoạn thẳng, vùng tô màu và ký hiệu T1/T2/T3           |
//+------------------------------------------------------------------+
void DrawTrendSeg(string name, datetime t1, double p1, datetime t2, double p2, color clr, int width, ENUM_LINE_STYLE style = STYLE_SOLID)
{
   string obj = VIS_PREFIX + name;
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, obj, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, obj, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, obj, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, obj, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, obj, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, obj, OBJPROP_STYLE, style);
}

void DrawVisZone(string name, datetime t1, datetime t2, double p1, double p2, color rawClr, double alphaPct, bool show)
{
   string obj = VIS_PREFIX + name;
   if(!show || p1 <= 0.0 || p2 <= 0.0 || MathAbs(p1 - p2) < _Point * 0.5)
   {
      ObjectDelete(0, obj);
      return;
   }
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, obj, OBJPROP_FILL, true);
      ObjectSetInteger(0, obj, OBJPROP_BACK, true);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   }
   color blended = BlendWithBg(rawClr, alphaPct);
   ObjectSetInteger(0, obj, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, obj, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, obj, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, obj, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, blended);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, blended);
}

void DrawMarkerSymbol(string name, datetime t, double price, string sym, color clr, int fontSizeOffset = 1)
{
   string obj = VIS_PREFIX + name;
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_TEXT, 0, t, price);
      ObjectSetString(0, obj, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetInteger(0, obj, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, obj, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, obj, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, InpFontSize + fontSizeOffset);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetString(0, obj, OBJPROP_TEXT, sym);
}

//+------------------------------------------------------------------+
//| Vẽ Spotlight T1 / T2 / T3 ở mép phải (Đã sửa lỗi cắt chữ mép phải)|
//+------------------------------------------------------------------+
void DrawCurrentAtrSpotlight(double currentTrailPrice, double ref1RDist, ENUM_TRADE_SIDE sideParam,
                             int openOrders, double currentBrokerSL, bool isViolated, double currentR, bool isTrailArmed)
{
   string t1Ray   = VIS_PREFIX + "SPOT_RAY";
   string t1Badge = VIS_PREFIX + "SPOT_BADGE";
   string t1Tag   = VIS_PREFIX + "SPOT_TAG";

   string t2Ray   = VIS_PREFIX + "SPOT_T2_RAY";
   string t2Badge = VIS_PREFIX + "SPOT_T2_BADGE";
   string t2Tag   = VIS_PREFIX + "SPOT_T2_TAG";

   string t3Ray   = VIS_PREFIX + "SPOT_T3_RAY";
   string t3Badge = VIS_PREFIX + "SPOT_T3_BADGE";
   string t3Tag   = VIS_PREFIX + "SPOT_T3_TAG";

   if(!g_showAtrPlot || currentTrailPrice <= 0.0)
   {
      ObjectDelete(0, t1Ray); ObjectDelete(0, t1Badge); ObjectDelete(0, t1Tag);
      ObjectDelete(0, t2Ray); ObjectDelete(0, t2Badge); ObjectDelete(0, t2Tag);
      ObjectDelete(0, t3Ray); ObjectDelete(0, t3Badge); ObjectDelete(0, t3Tag);
      DrawVisZone("Z_T1_T2", 0, 0, 0, 0, clrNONE, 0, false);
      DrawVisZone("Z_T2_T3", 0, 0, 0, 0, clrNONE, 0, false);
      return;
   }

   datetime bar0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   int sec = PeriodSeconds(PERIOD_CURRENT);
   if(sec <= 0) sec = 60;

   datetime tEnd   = bar0 + sec * 14;
   datetime tLabel = bar0 + sec * 13; // Neo phải từ tLabel ngược về bên trái để không bao giờ tràn mép phải
   string tfName   = GetTfShortName(g_resolvedAtrTf);

   // --- TẦNG 1 (T1): ĐƯỜNG ATR CHÍNH ---
   if(ObjectFind(0, t1Ray) < 0)
   {
      ObjectCreate(0, t1Ray, OBJ_TREND, 0, bar0, currentTrailPrice, tEnd, currentTrailPrice);
      ObjectSetInteger(0, t1Ray, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, t1Ray, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, t1Ray, OBJPROP_TIME, 0, bar0);
   ObjectSetDouble(0, t1Ray, OBJPROP_PRICE, 0, currentTrailPrice);
   ObjectSetInteger(0, t1Ray, OBJPROP_TIME, 1, tEnd);
   ObjectSetDouble(0, t1Ray, OBJPROP_PRICE, 1, currentTrailPrice);
   ObjectSetInteger(0, t1Ray, OBJPROP_COLOR, C_TIER1_RAY);
   ObjectSetInteger(0, t1Ray, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, t1Ray, OBJPROP_STYLE, STYLE_SOLID);

   if(ObjectFind(0, t1Badge) < 0)
   {
      ObjectCreate(0, t1Badge, OBJ_ARROW_RIGHT_PRICE, 0, tEnd, currentTrailPrice);
      ObjectSetInteger(0, t1Badge, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, t1Badge, OBJPROP_TIME, 0, tEnd);
   ObjectSetDouble(0, t1Badge, OBJPROP_PRICE, 0, currentTrailPrice);
   ObjectSetInteger(0, t1Badge, OBJPROP_COLOR, C_TIER1_RAY);

   double liveClose = iClose(_Symbol, PERIOD_CURRENT, 0);
   double distPts   = (_Point > 0.0) ? (MathAbs(liveClose - currentTrailPrice) / _Point) : 0.0;

   string t1Text = StringFormat("T1 [ATR %s: %s | %.0f đ] Rút râu = giữ (%d nến) ",
                                tfName, DoubleToString(currentTrailPrice, _Digits), distPts, g_tier1SavedCount);

   if(ObjectFind(0, t1Tag) < 0)
   {
      ObjectCreate(0, t1Tag, OBJ_TEXT, 0, tLabel, currentTrailPrice);
      ObjectSetString(0, t1Tag, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetInteger(0, t1Tag, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, t1Tag, OBJPROP_ANCHOR, (sideParam == SIDE_LONG) ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, t1Tag, OBJPROP_TIME, 0, tLabel);
   ObjectSetDouble(0, t1Tag, OBJPROP_PRICE, 0, currentTrailPrice);
   ObjectSetInteger(0, t1Tag, OBJPROP_FONTSIZE, MathMax(8, InpFontSize - 1));
   ObjectSetInteger(0, t1Tag, OBJPROP_COLOR, (g_enTrail && isTrailArmed) ? clrLime : C_TIER1_RAY);
   ObjectSetString(0, t1Tag, OBJPROP_TEXT, t1Text);

   // --- TẦNG 2 (T2) & TẦNG 3 (T3): VÙNG ĐỆM CHỐNG QUÉT 3 TẦNG ---
   double base1R = (ref1RDist > 0.0) ? ref1RDist
                   : ((g_pineFirstBarSlDist > 0.0) ? g_pineFirstBarSlDist : (g_pineLatestAtr * g_customValueForFirstDay));
   double buffer20Pct1R = base1R * (g_tierPctOf1R / 100.0);
   double buffer10Pct1R = buffer20Pct1R * 0.5;

   if(g_sweepMode == SWEEP_3LAYER_20PCT_1R && buffer20Pct1R > 0.0)
   {
      double tier2Price = (sideParam == SIDE_LONG) ? NormalizeDouble(currentTrailPrice - buffer10Pct1R, _Digits)
                                                   : NormalizeDouble(currentTrailPrice + buffer10Pct1R, _Digits);
      double tier3Price = (sideParam == SIDE_LONG) ? NormalizeDouble(currentTrailPrice - buffer20Pct1R, _Digits)
                                                   : NormalizeDouble(currentTrailPrice + buffer20Pct1R, _Digits);

      double t2Pts = (_Point > 0.0) ? (buffer10Pct1R / _Point) : 0.0;
      double t3Pts = (_Point > 0.0) ? (buffer20Pct1R / _Point) : 0.0;

      DrawVisZone("Z_T1_T2", bar0, tEnd, currentTrailPrice, tier2Price, C_TIER2_RAY, 10.0, true);
      DrawVisZone("Z_T2_T3", bar0, tEnd, tier2Price,        tier3Price, C_TIER3_RAY, 14.0, true);

      // Tầng 2
      if(ObjectFind(0, t2Ray) < 0)
      {
         ObjectCreate(0, t2Ray, OBJ_TREND, 0, bar0, tier2Price, tEnd, tier2Price);
         ObjectSetInteger(0, t2Ray, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, t2Ray, OBJPROP_SELECTABLE, false);
      }
      ObjectSetInteger(0, t2Ray, OBJPROP_TIME, 0, bar0);
      ObjectSetDouble(0, t2Ray, OBJPROP_PRICE, 0, tier2Price);
      ObjectSetInteger(0, t2Ray, OBJPROP_TIME, 1, tEnd);
      ObjectSetDouble(0, t2Ray, OBJPROP_PRICE, 1, tier2Price);
      ObjectSetInteger(0, t2Ray, OBJPROP_COLOR, C_TIER2_RAY);
      ObjectSetInteger(0, t2Ray, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, t2Ray, OBJPROP_STYLE, STYLE_DASH);

      if(ObjectFind(0, t2Badge) < 0)
      {
         ObjectCreate(0, t2Badge, OBJ_ARROW_RIGHT_PRICE, 0, tEnd, tier2Price);
         ObjectSetInteger(0, t2Badge, OBJPROP_SELECTABLE, false);
      }
      ObjectSetInteger(0, t2Badge, OBJPROP_TIME, 0, tEnd);
      ObjectSetDouble(0, t2Badge, OBJPROP_PRICE, 0, tier2Price);
      ObjectSetInteger(0, t2Badge, OBJPROP_COLOR, C_TIER2_RAY);

      string t2Text = StringFormat("T2 [CẮT 50%%: %s | %.0f%% 1R=%.0f đ] Đóng nến %s (%d lần) ",
                                   DoubleToString(tier2Price, _Digits), g_tierPctOf1R * 0.5, t2Pts, tfName, g_tier2HalfCutCount);
      if(ObjectFind(0, t2Tag) < 0)
      {
         ObjectCreate(0, t2Tag, OBJ_TEXT, 0, tLabel, tier2Price);
         ObjectSetString(0, t2Tag, OBJPROP_FONT, "Segoe UI Bold");
         ObjectSetInteger(0, t2Tag, OBJPROP_SELECTABLE, false);
      }
      ObjectSetInteger(0, t2Tag, OBJPROP_ANCHOR, ANCHOR_RIGHT);
      ObjectSetInteger(0, t2Tag, OBJPROP_TIME, 0, tLabel);
      ObjectSetDouble(0, t2Tag, OBJPROP_PRICE, 0, tier2Price);
      ObjectSetInteger(0, t2Tag, OBJPROP_FONTSIZE, MathMax(8, InpFontSize - 1));
      ObjectSetInteger(0, t2Tag, OBJPROP_COLOR, C_TIER2_RAY);
      ObjectSetString(0, t2Tag, OBJPROP_TEXT, t2Text);

      // Tầng 3
      if(ObjectFind(0, t3Ray) < 0)
      {
         ObjectCreate(0, t3Ray, OBJ_TREND, 0, bar0, tier3Price, tEnd, tier3Price);
         ObjectSetInteger(0, t3Ray, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, t3Ray, OBJPROP_SELECTABLE, false);
      }
      ObjectSetInteger(0, t3Ray, OBJPROP_TIME, 0, bar0);
      ObjectSetDouble(0, t3Ray, OBJPROP_PRICE, 0, tier3Price);
      ObjectSetInteger(0, t3Ray, OBJPROP_TIME, 1, tEnd);
      ObjectSetDouble(0, t3Ray, OBJPROP_PRICE, 1, tier3Price);
      ObjectSetInteger(0, t3Ray, OBJPROP_COLOR, C_TIER3_RAY);
      ObjectSetInteger(0, t3Ray, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, t3Ray, OBJPROP_STYLE, STYLE_DOT);

      if(ObjectFind(0, t3Badge) < 0)
      {
         ObjectCreate(0, t3Badge, OBJ_ARROW_RIGHT_PRICE, 0, tEnd, tier3Price);
         ObjectSetInteger(0, t3Badge, OBJPROP_SELECTABLE, false);
      }
      ObjectSetInteger(0, t3Badge, OBJPROP_TIME, 0, tEnd);
      ObjectSetDouble(0, t3Badge, OBJPROP_PRICE, 0, tier3Price);
      ObjectSetInteger(0, t3Badge, OBJPROP_COLOR, C_TIER3_RAY);

      string t3Text = StringFormat("T3 [SL 100%%: %s | %.0f%% 1R=%.0f đ] Thủng = đóng hết! ",
                                   DoubleToString(tier3Price, _Digits), g_tierPctOf1R, t3Pts);
      if(ObjectFind(0, t3Tag) < 0)
      {
         ObjectCreate(0, t3Tag, OBJ_TEXT, 0, tLabel, tier3Price);
         ObjectSetString(0, t3Tag, OBJPROP_FONT, "Segoe UI Bold");
         ObjectSetInteger(0, t3Tag, OBJPROP_SELECTABLE, false);
      }
      ObjectSetInteger(0, t3Tag, OBJPROP_ANCHOR, (sideParam == SIDE_LONG) ? ANCHOR_RIGHT_UPPER : ANCHOR_RIGHT_LOWER);
      ObjectSetInteger(0, t3Tag, OBJPROP_TIME, 0, tLabel);
      ObjectSetDouble(0, t3Tag, OBJPROP_PRICE, 0, tier3Price);
      ObjectSetInteger(0, t3Tag, OBJPROP_FONTSIZE, MathMax(8, InpFontSize - 1));
      ObjectSetInteger(0, t3Tag, OBJPROP_COLOR, C_TIER3_RAY);
      ObjectSetString(0, t3Tag, OBJPROP_TEXT, t3Text);
   }
   else
   {
      ObjectDelete(0, t2Ray); ObjectDelete(0, t2Badge); ObjectDelete(0, t2Tag);
      ObjectDelete(0, t3Ray); ObjectDelete(0, t3Badge); ObjectDelete(0, t3Tag);
      DrawVisZone("Z_T1_T2", 0, 0, 0, 0, clrNONE, 0, false);
      DrawVisZone("Z_T2_T3", 0, 0, 0, 0, clrNONE, 0, false);
   }
}

//+------------------------------------------------------------------+
//| Tính mảng ATR chuẩn Pine Script RMA (Wilder's Smoothing)         |
//+------------------------------------------------------------------+
void ComputeExactPineAtrArray(const MqlRates &rates[], int total, int length, double &outAtr[])
{
   ArrayResize(outAtr, total);
   ArrayInitialize(outAtr, 0.0);
   if(total <= 0)
      return;

   int len = MathMax(1, length);
   double sumTR = 0.0;

   for(int i = 0; i < total; i++)
   {
      double high_i = rates[i].high;
      double low_i  = rates[i].low;
      double tr     = high_i - low_i;

      if(i > 0)
      {
         double prevClose = rates[i - 1].close;
         double trHC = MathAbs(high_i - prevClose);
         double trLC = MathAbs(low_i  - prevClose);
         if(trHC > tr) tr = trHC;
         if(trLC > tr) tr = trLC;
      }

      if(i < len - 1)
      {
         sumTR    += tr;
         outAtr[i] = sumTR / (double)(i + 1);
      }
      else if(i == len - 1)
      {
         sumTR    += tr;
         outAtr[i] = sumTR / (double)len;
      }
      else
      {
         outAtr[i] = (outAtr[i - 1] * (double)(len - 1) + tr) / (double)len;
      }
   }
}

//+------------------------------------------------------------------+
//| Kiểm tra tính hợp lệ của Bộ nhớ đệm theo nến (Bar-Open Cache)    |
//+------------------------------------------------------------------+
bool IsAtrBarCacheMatch(ENUM_TIMEFRAMES calcTf, datetime closedBarTime, datetime entryDate,
                        double entryPriceParam, ENUM_TRADE_SIDE sideParam, bool allowAutoRestart)
{
   if(!InpEnableAtrBarCache || !g_atrCacheValid || closedBarTime <= 0)
      return false;
   if(g_atrCacheKey.symbol           != _Symbol)                  return false;
   if(g_atrCacheKey.calcTf           != calcTf)                   return false;
   if(g_atrCacheKey.lastClosedBarTime!= closedBarTime)            return false;
   if(g_atrCacheKey.anchorTime       != entryDate)                return false;
   if(MathAbs(g_atrCacheKey.entryPriceParam - entryPriceParam) > _Point * 0.1) return false;
   if(g_atrCacheKey.sideParam        != sideParam)                return false;
   if(g_atrCacheKey.atrLen           != g_atrLength)              return false;
   if(MathAbs(g_atrCacheKey.firstMul - g_customValueForFirstDay) > 1e-6) return false;
   if(MathAbs(g_atrCacheKey.atrMul   - g_atrMultiplier) > 1e-6)   return false;
   if(g_atrCacheKey.atrSrc           != g_atrSource)              return false;
   if(g_atrCacheKey.sweepMode        != g_sweepMode)              return false;
   if(MathAbs(g_atrCacheKey.tierPct1R - g_tierPctOf1R) > 1e-4)    return false;
   if(g_atrCacheKey.swingLookback    != g_swingLookback)          return false;
   if(g_atrCacheKey.allowAutoRestart != allowAutoRestart)         return false;
   if(MathAbs(g_atrCacheKey.trailStartRR - g_trailStartRR) > 1e-4) return false;
   return true;
}

void SaveAtrBarCacheState(ENUM_TIMEFRAMES calcTf, datetime closedBarTime, datetime entryDate,
                          double entryPriceParam, ENUM_TRADE_SIDE sideParam, bool allowAutoRestart, double trailResult)
{
   g_atrCacheKey.symbol            = _Symbol;
   g_atrCacheKey.calcTf            = calcTf;
   g_atrCacheKey.lastClosedBarTime = closedBarTime;
   g_atrCacheKey.anchorTime        = entryDate;
   g_atrCacheKey.entryPriceParam   = entryPriceParam;
   g_atrCacheKey.sideParam         = sideParam;
   g_atrCacheKey.atrLen            = g_atrLength;
   g_atrCacheKey.firstMul          = g_customValueForFirstDay;
   g_atrCacheKey.atrMul            = g_atrMultiplier;
   g_atrCacheKey.atrSrc            = g_atrSource;
   g_atrCacheKey.sweepMode         = g_sweepMode;
   g_atrCacheKey.tierPct1R         = g_tierPctOf1R;
   g_atrCacheKey.swingLookback     = g_swingLookback;
   g_atrCacheKey.allowAutoRestart  = allowAutoRestart;
   g_atrCacheKey.trailStartRR      = g_trailStartRR;
   g_cachedTrailResult             = trailResult;
   g_atrCacheValid                 = true;
}

//+------------------------------------------------------------------+
//| Thực thi công thức ATR Neo chuẩn Pine + Cache + Gộp đoạn ngang   |
//+------------------------------------------------------------------+
double ExecuteExactPineScriptFormula(ENUM_TIMEFRAMES calcTf,
                                     datetime entryDate,
                                     double entryPriceParam,
                                     ENUM_TRADE_SIDE sideParam,
                                     bool drawPlotOnChart,
                                     bool allowAutoRestart,
                                     double &outEntryLevel,
                                     double &outFirstBarSlDist,
                                     bool &outStopPlotting,
                                     bool &outStartCalculating,
                                     bool &outDataReady)
{
   outEntryLevel       = 0.0;
   outFirstBarSlDist   = 0.0;
   outStopPlotting     = false;
   outStartCalculating = false;
   outDataReady        = false;

   datetime pingTfBar0 = iTime(_Symbol, calcTf, 0);
   datetime closedBar1 = iTime(_Symbol, calcTf, 1);
   if(pingTfBar0 <= 0)
      return 0.0;

   // Kiểm tra Bar-Open Cache khi đang vẽ đường ATR chính trên biểu đồ:
   // Nếu nến đóng gần nhất chưa đổi, chỉ kiểm tra va chạm T3 của nến đang chạy (bar 0) và kéo dài đoạn H0
   if(drawPlotOnChart && IsAtrBarCacheMatch(calcTf, closedBar1, entryDate, entryPriceParam, sideParam, allowAutoRestart))
   {
      outEntryLevel       = g_pineEntryLevel;
      outFirstBarSlDist   = g_pineFirstBarSlDist;
      outStopPlotting     = g_pineStopPlotting;
      outStartCalculating = g_pineStartCalc;
      outDataReady        = true;

      if(!g_pineStopPlotting && g_cachedTrailResult > 0.0)
      {
         double bar0High = iHigh(_Symbol, calcTf, 0);
         double bar0Low  = iLow(_Symbol, calcTf, 0);
         double ref1R    = (g_pineFirstBarSlDist > 0.0) ? g_pineFirstBarSlDist : (g_pineLatestAtr * g_customValueForFirstDay);
         double tierBuf  = ref1R * (g_tierPctOf1R / 100.0);
         double hardBnd  = (sideParam == SIDE_LONG) ? (g_cachedTrailResult - tierBuf) : (g_cachedTrailResult + tierBuf);

         bool intrabarBreak = false;
         if(g_sweepMode == SWEEP_3LAYER_20PCT_1R)
            intrabarBreak = (sideParam == SIDE_LONG) ? (bar0Low <= hardBnd) : (bar0High >= hardBnd);
         else if(g_sweepMode == SWEEP_HARD_SL_ON_LINE)
            intrabarBreak = (sideParam == SIDE_LONG) ? (bar0Low < g_cachedTrailResult) : (bar0High > g_cachedTrailResult);
         // Lưu ý: SWEEP_WAIT_CANDLE_CLOSE tuyệt đối không gãy intrabar

         if(intrabarBreak)
         {
            g_atrCacheValid = false; // Bắt buộc tính lại để vẽ dấu T3
         }
         else
         {
            datetime chartBar0 = iTime(_Symbol, PERIOD_CURRENT, 0);
            datetime endPlot   = MathMax(pingTfBar0, chartBar0);
            color plotClr      = (sideParam == SIDE_LONG) ? C_ATR_LONG : C_ATR_SHORT;
            DrawTrendSeg("ATRLINE_H0", pingTfBar0, g_cachedTrailResult, endPlot, g_cachedTrailResult, plotClr, 3);
            return g_cachedTrailResult;
         }
      }
      else
      {
         return g_cachedTrailResult;
      }
   }

   int anchorShift = iBarShift(_Symbol, calcTf, entryDate, false);
   if(anchorShift < 0)
      return 0.0;

   int visualShift = MathMax(anchorShift, 60);
   int barsToCopy  = MathMin(visualShift + g_atrLength * 8 + 120, 5000);
   barsToCopy      = MathMax(barsToCopy, g_atrLength * 4 + 80);

   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int copied = CopyRates(_Symbol, calcTf, 0, barsToCopy, rates);
   if(copied < g_atrLength + 2 || anchorShift >= copied)
      return 0.0;

   double atrArr[];
   ComputeExactPineAtrArray(rates, copied, g_atrLength, atrArr);

   g_pineLatestAtr = (copied >= 2) ? atrArr[copied - 2] : atrArr[copied - 1];

   int anchorIdx = copied - 1 - anchorShift;
   if(anchorIdx < g_atrLength - 1 || anchorIdx >= copied)
      return 0.0;
   outDataReady = true;

   if(drawPlotOnChart)
   {
      ObjectsDeleteAll(0, VIS_PREFIX + "ATRLINE_");
      g_tier1SavedCount   = 0;
      g_tier2HalfCutCount = 0;
   }

   datetime effectiveEntryDate = rates[anchorIdx].time;

   bool     hasEntryLevel        = false;
   double   entryLevel           = 0.0;
   bool     hasPrevTrailing      = false;
   double   prevTrailingStop     = 0.0;
   double   trailingStop         = 0.0;
   bool     firstDayCalculated   = false;
   bool     stopPlotting         = false;
   bool     tier2TriggeredCycle  = false;
   bool     trailArmedInLoop     = allowAutoRestart;
   datetime armedTriggerBarTime  = 0;

   // Biến phục vụ thuật toán gộp đoạn ngang liên tiếp (Segment Coalescing)
   datetime segStartTime         = 0;
   datetime prevPlottedTime      = 0;
   double   prevPlottedValue     = 0.0;
   int      segCounter           = 0;
   color    plotColor            = (sideParam == SIDE_LONG) ? C_ATR_LONG : C_ATR_SHORT;
   datetime chartBar0            = iTime(_Symbol, PERIOD_CURRENT, 0);

   for(int i = 0; i < copied; i++)
   {
      datetime barTime       = rates[i].time;
      double   barClose      = rates[i].close;
      double   barHigh       = rates[i].high;
      double   barLow        = rates[i].low;
      double   atrValue      = (i == copied - 1 && i > 0) ? atrArr[i - 1] : atrArr[i];
      bool     isFormingBar0 = (i == copied - 1);

      if(!hasEntryLevel && barTime >= effectiveEntryDate)
      {
         entryLevel    = (entryPriceParam > 0.0) ? entryPriceParam : barClose;
         hasEntryLevel = true;
         outEntryLevel = entryLevel;
      }

      bool startCalculating = (hasEntryLevel && barTime >= effectiveEntryDate);
      if(startCalculating)
         outStartCalculating = true;

      if(startCalculating && !stopPlotting)
      {
         double ref1R = (outFirstBarSlDist > 0.0) ? outFirstBarSlDist : (atrValue * g_customValueForFirstDay);

         if(!trailArmedInLoop && ref1R > 0.0)
         {
            double bestExtent = (sideParam == SIDE_LONG) ? (barHigh - entryLevel) : (entryLevel - barLow);
            if((bestExtent / ref1R) >= g_trailStartRR - 1e-6)
            {
               trailArmedInLoop    = true;
               armedTriggerBarTime = barTime;
            }
         }

         if(!hasPrevTrailing)
         {
            if(sideParam == SIDE_LONG)
            {
               if(!firstDayCalculated)
               { trailingStop = entryLevel - atrValue * g_customValueForFirstDay; firstDayCalculated = true; }
               else
                  trailingStop = entryLevel - g_atrMultiplier * atrValue;
            }
            else
            {
               if(!firstDayCalculated)
               { trailingStop = entryLevel + atrValue * g_customValueForFirstDay; firstDayCalculated = true; }
               else
                  trailingStop = entryLevel + g_atrMultiplier * atrValue;
            }
            outFirstBarSlDist   = MathAbs(entryLevel - trailingStop);
            ref1R               = outFirstBarSlDist;
            tier2TriggeredCycle = false;

            if(!trailArmedInLoop && ref1R > 0.0)
            {
               double bestExtent0 = (sideParam == SIDE_LONG) ? (barHigh - entryLevel) : (entryLevel - barLow);
               if((bestExtent0 / ref1R) >= g_trailStartRR - 1e-6)
               {
                  trailArmedInLoop    = true;
                  armedTriggerBarTime = barTime;
               }
            }
         }
         else
         {
            if(!trailArmedInLoop || (!allowAutoRestart && barTime <= armedTriggerBarTime))
            {
               trailingStop = prevTrailingStop;
            }
            else if(g_atrSource == ATR_SRC_CLOSE_SWING)
            {
               if(isFormingBar0)
               {
                  trailingStop = prevTrailingStop;
               }
               else
               {
                  if(sideParam == SIDE_LONG)
                  {
                     double newStop = barClose - g_atrMultiplier * atrValue;
                     double lowestRecent = barLow;
                     for(int k = 1; k <= g_swingLookback && (i - k) >= 0; k++)
                        if(rates[i - k].low < lowestRecent)
                           lowestRecent = rates[i - k].low;

                     double swingCap = lowestRecent - atrValue * 0.25;
                     if(newStop > swingCap && barClose > lowestRecent)
                        newStop = MathMin(newStop, lowestRecent - _Point * 10);

                     trailingStop = MathMax(prevTrailingStop, newStop);
                  }
                  else
                  {
                     double newStop = barClose + g_atrMultiplier * atrValue;
                     double highestRecent = barHigh;
                     for(int k = 1; k <= g_swingLookback && (i - k) >= 0; k++)
                        if(rates[i - k].high > highestRecent)
                           highestRecent = rates[i - k].high;

                     double swingCap = highestRecent + atrValue * 0.25;
                     if(newStop < swingCap && barClose < highestRecent)
                        newStop = MathMax(newStop, highestRecent + _Point * 10);

                     trailingStop = MathMin(prevTrailingStop, newStop);
                  }
               }
            }
            else
            {
               if(sideParam == SIDE_LONG)
               {
                  double newStop = barHigh - g_atrMultiplier * atrValue;
                  trailingStop = MathMax(prevTrailingStop, newStop);
               }
               else
               {
                  double newStop = barLow + g_atrMultiplier * atrValue;
                  trailingStop = MathMin(prevTrailingStop, newStop);
               }
            }
         }

         double tierBuffer20   = ref1R * (g_tierPctOf1R / 100.0);
         bool   tier1WickSaved = false;
         bool   tier2HalfCut   = false;
         bool   tier3FullBreak = false;

         if(hasPrevTrailing && (allowAutoRestart || (trailArmedInLoop && barTime > armedTriggerBarTime)))
         {
            double tier3HardBoundary = (sideParam == SIDE_LONG) ? (prevTrailingStop - tierBuffer20)
                                                                : (prevTrailingStop + tierBuffer20);

            if(g_sweepMode == SWEEP_3LAYER_20PCT_1R)
            {
               if(sideParam == SIDE_LONG)
               {
                  if(barLow <= tier3HardBoundary)
                     tier3FullBreak = true;
                  else if(!isFormingBar0)
                  {
                     if(barLow < prevTrailingStop && barClose >= prevTrailingStop)
                        tier1WickSaved = true;
                     else if(barClose < prevTrailingStop && barClose > tier3HardBoundary)
                     {
                        if(!tier2TriggeredCycle)
                        { tier2HalfCut = true; tier2TriggeredCycle = true; }
                        else
                           tier3FullBreak = true;
                     }
                  }
               }
               else
               {
                  if(barHigh >= tier3HardBoundary)
                     tier3FullBreak = true;
                  else if(!isFormingBar0)
                  {
                     if(barHigh > prevTrailingStop && barClose <= prevTrailingStop)
                        tier1WickSaved = true;
                     else if(barClose > prevTrailingStop && barClose < tier3HardBoundary)
                     {
                        if(!tier2TriggeredCycle)
                        { tier2HalfCut = true; tier2TriggeredCycle = true; }
                        else
                           tier3FullBreak = true;
                     }
                  }
               }
            }
            else if(g_sweepMode == SWEEP_WAIT_CANDLE_CLOSE)
            {
               if(!isFormingBar0)
               {
                  if(sideParam == SIDE_LONG)
                  {
                     if(barClose < prevTrailingStop) tier3FullBreak = true;
                     else if(barLow < prevTrailingStop && barClose >= prevTrailingStop) tier1WickSaved = true;
                  }
                  else
                  {
                     if(barClose > prevTrailingStop) tier3FullBreak = true;
                     else if(barHigh > prevTrailingStop && barClose <= prevTrailingStop) tier1WickSaved = true;
                  }
               }
            }
            else
            {
               if(sideParam == SIDE_LONG  && barLow  < prevTrailingStop) tier3FullBreak = true;
               if(sideParam == SIDE_SHORT && barHigh > prevTrailingStop) tier3FullBreak = true;
            }
         }

         if(tier1WickSaved && drawPlotOnChart)
         {
            g_tier1SavedCount++;
            double markP = (sideParam == SIDE_LONG) ? barLow : barHigh;
            DrawMarkerSymbol("ATRLINE_T1_" + IntegerToString(i), barTime, markP, "T1", clrAqua, -1);
         }

         if(tier2HalfCut && drawPlotOnChart)
         {
            g_tier2HalfCutCount++;
            double markP = (sideParam == SIDE_LONG) ? barLow : barHigh;
            DrawMarkerSymbol("ATRLINE_T2_" + IntegerToString(i), barTime, markP, "T2-50%", C_TIER2_RAY, -1);
         }

         if(tier3FullBreak)
         {
            outStopPlotting = true;
            if(drawPlotOnChart)
            {
               if(segStartTime > 0 && prevPlottedTime > 0)
               {
                  segCounter++;
                  DrawTrendSeg("ATRLINE_H_" + IntegerToString(segCounter), segStartTime, prevPlottedValue, barTime, prevPlottedValue, plotColor, 3);
               }
               DrawMarkerSymbol("ATRLINE_T3_" + IntegerToString(i), barTime, prevTrailingStop, "T3", C_TIER3_RAY, 0);
            }

            if(allowAutoRestart && i < copied - 1)
            {
               entryLevel          = barClose;
               outEntryLevel       = entryLevel;
               firstDayCalculated  = true;
               trailingStop        = (sideParam == SIDE_LONG) ? (entryLevel - atrValue * g_customValueForFirstDay)
                                                              : (entryLevel + atrValue * g_customValueForFirstDay);
               outFirstBarSlDist   = MathAbs(entryLevel - trailingStop);
               outStopPlotting     = false;
               tier2TriggeredCycle = false;
               segStartTime        = 0;
               prevPlottedTime     = 0;
            }
            else
            {
               stopPlotting = true;
            }
         }

         if(!stopPlotting)
         {
            hasPrevTrailing  = true;
            prevTrailingStop = trailingStop;

            if(drawPlotOnChart)
            {
               if(segStartTime == 0)
               {
                  segStartTime     = barTime;
                  prevPlottedTime  = barTime;
                  prevPlottedValue = trailingStop;
               }
               else if(MathAbs(trailingStop - prevPlottedValue) >= _Point * 0.5)
               {
                  // Kết thúc đoạn ngang cũ và vẽ đoạn bậc thang dọc sang mức giá mới
                  segCounter++;
                  DrawTrendSeg("ATRLINE_H_" + IntegerToString(segCounter), segStartTime, prevPlottedValue, barTime, prevPlottedValue, plotColor, 3);
                  DrawTrendSeg("ATRLINE_V_" + IntegerToString(segCounter), barTime, prevPlottedValue, barTime, trailingStop, plotColor, 2);
                  segStartTime     = barTime;
                  prevPlottedValue = trailingStop;
               }
               prevPlottedTime = barTime;

               if(i == copied - 1)
               {
                  if(segStartTime > 0 && segStartTime < barTime)
                  {
                     segCounter++;
                     DrawTrendSeg("ATRLINE_H_" + IntegerToString(segCounter), segStartTime, prevPlottedValue, barTime, prevPlottedValue, plotColor, 3);
                  }
                  datetime endPlotTime = MathMax(barTime, chartBar0);
                  DrawTrendSeg("ATRLINE_H0", barTime, trailingStop, endPlotTime, trailingStop, plotColor, 3);
               }
            }
         }
      }
   }

   if(drawPlotOnChart)
   {
      SaveAtrBarCacheState(calcTf, closedBar1, entryDate, entryPriceParam, sideParam, allowAutoRestart, trailingStop);
   }
   return trailingStop;
}

// ============================================================================
// MODULE 4: CTrailingAndBeSuite (9 TRAILING MODES, 4-STAGE BE & COMMON BE)
// ============================================================================

//+------------------------------------------------------------------+
//| Kiểm tra một ngưỡng kích hoạt (RR, Points, %TP, Giá) đã đạt chưa |
//+------------------------------------------------------------------+
bool EvaluateTriggerReached(ENUM_TRIGGER_UNIT unit, double trigVal, bool isBuy,
                            double entry, double oneR, double currentR,
                            double currentProfitPts, double tpPrice, double livePrice)
{
   if(trigVal <= 0.0)
      return false;
   switch(unit)
   {
      case UNIT_RR:
         return (currentR >= trigVal - 1e-6);
      case UNIT_PIPS_POINTS:
         return (currentProfitPts >= trigVal - 1e-4);
      case UNIT_PCT_OF_TP:
      {
         if(tpPrice <= 0.0 || entry <= 0.0)
            return false;
         double totalTpDist = MathAbs(tpPrice - entry);
         if(totalTpDist <= _Point)
            return false;
         double curDist = isBuy ? (livePrice - entry) : (entry - livePrice);
         return ((curDist / totalTpDist) * 100.0 >= trigVal - 1e-4);
      }
      case UNIT_PRICE:
         return isBuy ? (livePrice >= trigVal - _Point * 0.1) : (livePrice <= trigVal + _Point * 0.1);
   }
   return false;
}

//+------------------------------------------------------------------+
//| Quy đổi mức khóa lợi nhuận của Breakeven sang mức giá tuyệt đối  |
//+------------------------------------------------------------------+
double ComputeLockLevelPrice(ENUM_TRIGGER_UNIT lockUnit, double lockVal, bool isBuy,
                             double entry, double oneR, double currentProfitPts, double tpPrice)
{
   string execSym = GetExecutionSymbol();
   double sign    = isBuy ? 1.0 : -1.0;
   double rawPx   = entry;

   switch(lockUnit)
   {
      case UNIT_RR:
         rawPx = entry + sign * (oneR * lockVal);
         break;
      case UNIT_PIPS_POINTS:
         rawPx = entry + sign * (lockVal * _Point);
         break;
      case UNIT_PCT_OF_TP:
         if(tpPrice > 0.0 && MathAbs(tpPrice - entry) > _Point)
            rawPx = entry + sign * (MathAbs(tpPrice - entry) * (lockVal / 100.0));
         else
            rawPx = entry + sign * (currentProfitPts * _Point * (lockVal / 100.0));
         break;
      case UNIT_PRICE:
         rawPx = lockVal;
         break;
   }
   return NormalizePriceToTickSize(execSym, rawPx);
}

//+------------------------------------------------------------------+
//| Thực thi Breakeven 4 cấp tuần tự và lưu Bitmask trạng thái       |
//+------------------------------------------------------------------+
void ApplyStepBreakEven(long posId, bool isBuy, double entry, double oneR,
                        double currentR, double currentProfitPts, double tpPrice, double &targetSL)
{
   if(!InpEnableStepBreakEven || entry <= 0.0 || oneR <= 0.0)
      return;

   string execSym  = GetExecutionSymbol();
   double livePx   = isBuy ? SymbolInfoDouble(execSym, SYMBOL_BID) : SymbolInfoDouble(execSym, SYMBOL_ASK);
   string maskKey  = (posId > 0) ? StepBeMaskKey(posId) : "";

   for(int s = 0; s < 4; s++)
   {
      if(!g_beStages[s].enabled)
         continue;

      // Cấp sau chỉ kích hoạt khi cấp trước đã hoàn tất (nếu cấp trước có bật)
      if(s > 0 && g_beStages[s - 1].enabled && posId > 0 && !IsTierBitSet(maskKey, s - 1))
      {
         bool prevNow = EvaluateTriggerReached(g_beStages[s - 1].triggerUnit, g_beStages[s - 1].triggerVal,
                                               isBuy, entry, oneR, currentR, currentProfitPts, tpPrice, livePx);
         if(!prevNow)
            break;
      }

      bool reached = EvaluateTriggerReached(g_beStages[s].triggerUnit, g_beStages[s].triggerVal,
                                            isBuy, entry, oneR, currentR, currentProfitPts, tpPrice, livePx);
      if(!reached && (posId <= 0 || !IsTierBitSet(maskKey, s)))
         continue;

      if(posId > 0 && reached && !IsTierBitSet(maskKey, s))
         SetTierBit(maskKey, s);

      double candidate = ComputeLockLevelPrice(g_beStages[s].lockUnit, g_beStages[s].lockVal,
                                               isBuy, entry, oneR, currentProfitPts, tpPrice);
      if(candidate <= 0.0)
         continue;

      if(isBuy)
      {
         if(candidate > targetSL)
            targetSL = candidate;
      }
      else
      {
         if(targetSL <= 0.0 || candidate < targetSL)
            targetSL = candidate;
      }
   }
}

//+------------------------------------------------------------------+
//| Tổng hợp mức SL ứng viên từ BE cơ bản, Common BE, Lock & 4-Stage |
//+------------------------------------------------------------------+
double ComputePositionBeAndLockCandidate(long posId, bool isBuy, double entry, double vwapEntry,
                                         double oneR, double currentR, double tpPrice,
                                         double currentSL, string &outSource)
{
   outSource = "";
   if(g_trailStyle == TRAIL_STYLE_MANUAL_SL)
      return currentSL;

   string execSym = GetExecutionSymbol();
   double livePx  = isBuy ? SymbolInfoDouble(execSym, SYMBOL_BID) : SymbolInfoDouble(execSym, SYMBOL_ASK);
   double profPts = (_Point > 0.0) ? ((isBuy ? (livePx - entry) : (entry - livePx)) / _Point) : 0.0;
   double bestSL  = currentSL;

   // 1. Breakeven cơ bản & Common Break Even (VWAP + Phí + Swap)
   if(g_enBe && currentR >= g_beRR - 1e-6)
   {
      double baseEntry = (g_multiMode == MULTI_BASKET_VWAP && !g_mixedPositionFallback && vwapEntry > 0.0) ? vwapEntry : entry;
      double bePrice   = isBuy ? NormalizePriceToTickSize(execSym, baseEntry + g_bePoints * _Point)
                               : NormalizePriceToTickSize(execSym, baseEntry - g_bePoints * _Point);

      // Nếu bật Common BE trên rổ lệnh, ưu tiên mức Common BE đã bù phí và swap
      if(g_enCommonBe && g_multiMode == MULTI_BASKET_VWAP && !g_mixedPositionFallback && g_commonBePrice > 0.0)
      {
         if(isBuy && g_commonBePrice > bePrice)  bePrice = g_commonBePrice;
         if(!isBuy && g_commonBePrice < bePrice) bePrice = g_commonBePrice;
      }

      if(isBuy && bePrice > bestSL)
      { bestSL = bePrice; outSource = "BE"; }
      else if(!isBuy && (bestSL <= 0.0 || bePrice < bestSL))
      { bestSL = bePrice; outSource = "BE"; }
   }

   // 2. Lock Profit
   if(g_enLock && oneR > 0.0 && currentR >= g_lockTrigRR - 1e-6)
   {
      double baseEntry = (g_multiMode == MULTI_BASKET_VWAP && !g_mixedPositionFallback && vwapEntry > 0.0) ? vwapEntry : entry;
      double lockPrice = isBuy ? NormalizePriceToTickSize(execSym, baseEntry + oneR * g_lockLvlRR)
                               : NormalizePriceToTickSize(execSym, baseEntry - oneR * g_lockLvlRR);
      if(isBuy && lockPrice > bestSL)
      { bestSL = lockPrice; outSource = "LOCK_PROFIT"; }
      else if(!isBuy && (bestSL <= 0.0 || lockPrice < bestSL))
      { bestSL = lockPrice; outSource = "LOCK_PROFIT"; }
   }

   // 3. Multi-Level Breakeven 4 cấp
   double beforeStepBe = bestSL;
   ApplyStepBreakEven(posId, isBuy, entry, oneR, currentR, profPts, tpPrice, bestSL);
   if(MathAbs(bestSL - beforeStepBe) > _Point * 0.1)
      outSource = "STEP_BE_4";

   return bestSL;
}

//+------------------------------------------------------------------+
//| Khởi tạo Handle chỉ báo cho các phương pháp Trailing mở rộng     |
//+------------------------------------------------------------------+
bool EnsureAdvancedTrailHandle()
{
   if(g_advTrailMode == ADV_TRAIL_OFF ||
      g_advTrailMode == ADV_TRAIL_PIPS_BASIC ||
      g_advTrailMode == ADV_TRAIL_MULTI_4STAGE ||
      g_advTrailMode == ADV_TRAIL_HIGH_LOW_BAR ||
      g_advTrailMode == ADV_TRAIL_PARTIAL_STEP)
      return true;

   if(g_advTrailHandle != INVALID_HANDLE && g_advTrailHandleMode == g_advTrailMode)
      return true;
   if(g_advTrailHandle != INVALID_HANDLE)
      IndicatorRelease(g_advTrailHandle);
   g_advTrailHandle = INVALID_HANDLE;

   ENUM_TIMEFRAMES tf = (InpAdvancedTrailTimeframe == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpAdvancedTrailTimeframe;
   if(g_advTrailMode == ADV_TRAIL_MA)
      g_advTrailHandle = iMA(_Symbol, tf, MathMax(1, InpTrailMAPeriod), 0, InpTrailMAMethod, InpTrailMAAppliedPrice);
   else if(g_advTrailMode == ADV_TRAIL_FRACTAL)
      g_advTrailHandle = iFractals(_Symbol, tf);
   else if(g_advTrailMode == ADV_TRAIL_PSAR)
      g_advTrailHandle = iSAR(_Symbol, tf, MathMax(0.001, InpTrailSarStep), MathMax(InpTrailSarStep, InpTrailSarMaximum));
   else if(g_advTrailMode == ADV_TRAIL_ATR_SIMPLE)
      g_advTrailHandle = iATR(_Symbol, tf, MathMax(1, InpAtrLength));

   g_advTrailHandleMode = g_advTrailMode;
   return (g_advTrailHandle != INVALID_HANDLE);
}

//+------------------------------------------------------------------+
//| Tính mức SL đề xuất cho 8 phương pháp Trailing mở rộng (TA/FTM)  |
//+------------------------------------------------------------------+
double ComputeAdvancedTrailCandidateForPosition(ulong ticket, long posId, bool isBuy,
                                                double entry, double oneR, double currentR,
                                                double currentSL, double currentVol,
                                                double &outPartialStepCloseVol, string &outSource)
{
   outPartialStepCloseVol = 0.0;
   outSource              = "";
   if(g_advTrailMode == ADV_TRAIL_OFF || g_trailStyle == TRAIL_STYLE_MANUAL_SL)
      return currentSL;
   if(currentR < MathMax(0.0, InpAdvancedTrailStartR) - 1e-6)
      return currentSL;
   if(!EnsureAdvancedTrailHandle())
      return currentSL;

   string execSym = GetExecutionSymbol();
   MqlTick tick;
   if(!SymbolInfoTick(execSym, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      return currentSL;

   double livePx    = isBuy ? tick.bid : tick.ask;
   double profitPts = (_Point > 0.0) ? ((isBuy ? (livePx - entry) : (entry - livePx)) / _Point) : 0.0;
   double buffer    = MathMax(0, InpAdvancedTrailBufferPoints) * _Point;
   ENUM_TIMEFRAMES tf = (InpAdvancedTrailTimeframe == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpAdvancedTrailTimeframe;
   double candidate = 0.0;

   // --- Kiểu 1: Trailing Pips / Points cơ bản ---
   if(g_advTrailMode == ADV_TRAIL_PIPS_BASIC)
   {
      double dist = MathMax(1, InpTrailPipsDist) * _Point;
      double step = MathMax(1, InpTrailPipsStep) * _Point;
      if(profitPts * _Point >= dist)
      {
         double raw = isBuy ? (livePx - dist) : (livePx + dist);
         raw = NormalizePriceToTickSize(execSym, raw);
         bool stepOk = isBuy ? (raw >= currentSL + step - _Point * 0.1)
                             : (currentSL <= 0.0 || raw <= currentSL - step + _Point * 0.1);
         if(stepOk)
         { candidate = raw; outSource = "TRAIL_PIPS"; }
      }
   }
   // --- Kiểu 2: Trailing 4 cấp thu hẹp khoảng cách (Multi-Stage 4) ---
   else if(g_advTrailMode == ADV_TRAIL_MULTI_4STAGE)
   {
      int activeStage = -1;
      for(int s = 0; s < 4; s++)
      {
         if(g_multiTrailStages[s].enabled && profitPts >= g_multiTrailStages[s].triggerPts)
            activeStage = s;
      }
      if(activeStage >= 0)
      {
         double dist = g_multiTrailStages[activeStage].distPts * _Point;
         double step = g_multiTrailStages[activeStage].stepPts * _Point;
         double raw  = isBuy ? (livePx - dist) : (livePx + dist);
         raw = NormalizePriceToTickSize(execSym, raw);
         bool stepOk = isBuy ? (raw >= currentSL + step - _Point * 0.1)
                             : (currentSL <= 0.0 || raw <= currentSL - step + _Point * 0.1);
         if(stepOk)
         { candidate = raw; outSource = StringFormat("MULTI_TRAIL_S%d", activeStage + 1); }
      }
   }
   // --- Kiểu 3: Trailing theo đường MA (nến đã đóng) ---
   else if(g_advTrailMode == ADV_TRAIL_MA)
   {
      double v[];
      ArraySetAsSeries(v, true);
      if(CopyBuffer(g_advTrailHandle, 0, 1, 1, v) == 1 && v[0] > 0.0 && v[0] != EMPTY_VALUE)
      {
         candidate = NormalizePriceToTickSize(execSym, v[0] + (isBuy ? -buffer : buffer));
         outSource = "TRAIL_MA";
      }
   }
   // --- Kiểu 4: Trailing theo Parabolic SAR (nến đã đóng) ---
   else if(g_advTrailMode == ADV_TRAIL_PSAR)
   {
      double v[];
      ArraySetAsSeries(v, true);
      double c1 = iClose(_Symbol, tf, 1);
      if(CopyBuffer(g_advTrailHandle, 0, 1, 1, v) == 1 && v[0] > 0.0 && v[0] != EMPTY_VALUE)
      {
         if((isBuy && v[0] < c1) || (!isBuy && v[0] > c1))
         {
            candidate = NormalizePriceToTickSize(execSym, v[0] + (isBuy ? -buffer : buffer));
            outSource = "TRAIL_PSAR";
         }
      }
   }
   // --- Kiểu 5: Trailing theo Đỉnh/Đáy Fractals (nến đã đóng) ---
   else if(g_advTrailMode == ADV_TRAIL_FRACTAL)
   {
      int bufferIndex = isBuy ? 1 : 0; // Buffer 1 = Lower Fractal, Buffer 0 = Upper Fractal
      int search      = MathMax(3, MathMin(500, InpTrailFractalLookback));
      for(int shift = 2; shift <= search; shift++)
      {
         double f[];
         if(CopyBuffer(g_advTrailHandle, bufferIndex, shift, 1, f) != 1)
            continue;
         if(f[0] > 0.0 && f[0] != EMPTY_VALUE)
         {
            candidate = NormalizePriceToTickSize(execSym, f[0] + (isBuy ? -buffer : buffer));
            outSource = "TRAIL_FRACTAL";
            break;
         }
      }
   }
   // --- Kiểu 6: Trailing theo ATR đơn giản (không cần ngày neo) ---
   else if(g_advTrailMode == ADV_TRAIL_ATR_SIMPLE)
   {
      double a[];
      ArraySetAsSeries(a, true);
      double c1 = iClose(_Symbol, tf, 1);
      if(c1 > 0.0 && CopyBuffer(g_advTrailHandle, 0, 1, 1, a) == 1 && a[0] > 0.0)
      {
         double dist = a[0] * MathMax(0.1, InpSimpleAtrMult);
         candidate   = NormalizePriceToTickSize(execSym, c1 + (isBuy ? -dist : dist));
         outSource   = "TRAIL_ATR_SIMPLE";
      }
   }
   // --- Kiểu 7: Trailing theo Đỉnh/Đáy của K nến đã đóng gần nhất (High-Low Bar) ---
   else if(g_advTrailMode == ADV_TRAIL_HIGH_LOW_BAR)
   {
      int kBars = MathMax(1, MathMin(100, InpHighLowBarCount));
      double extreme = isBuy ? iLow(_Symbol, tf, 1) : iHigh(_Symbol, tf, 1);
      for(int b = 2; b <= kBars; b++)
      {
         double px = isBuy ? iLow(_Symbol, tf, b) : iHigh(_Symbol, tf, b);
         if(px <= 0.0) continue;
         if(isBuy && px < extreme)  extreme = px;
         if(!isBuy && px > extreme) extreme = px;
      }
      if(extreme > 0.0)
      {
         candidate = NormalizePriceToTickSize(execSym, extreme + (isBuy ? -buffer : buffer));
         outSource = "TRAIL_HIGHLOW_BAR";
      }
   }
   // --- Kiểu 8: Trailing bậc thang kết hợp cắt khối lượng (Partial-Close Step Trail) ---
   else if(g_advTrailMode == ADV_TRAIL_PARTIAL_STEP)
   {
      int stepPts = MathMax(10, InpPartialTrailStepPts);
      int completedSteps = (int)MathFloor(profitPts / (double)stepPts);
      if(completedSteps >= 1)
      {
         string stepKey = AccountScopedGV("TD_PSTEP_" + IntegerToString(posId));
         int savedSteps = GlobalVariableCheck(stepKey) ? (int)GlobalVariableGet(stepKey) : 0;
         if(completedSteps > savedSteps)
         {
            // Khóa SL tại nấc liền trước (completedSteps - 1) và yêu cầu cắt InpPartialTrailClosePct%
            double lockDist = (double)(completedSteps - 1) * stepPts * _Point;
            candidate       = NormalizePriceToTickSize(execSym, entry + (isBuy ? lockDist : -lockDist));
            outSource       = "TRAIL_PARTIAL_STEP";
            if(CanSplitVolume(currentVol, InpPartialTrailClosePct))
               outPartialStepCloseVol = FloorLotStep(currentVol * (InpPartialTrailClosePct / 100.0));
            GlobalVariableSet(stepKey, (double)completedSteps);
         }
      }
   }

   if(candidate <= 0.0)
      return currentSL;

   // Kiểm tra tính đơn điệu (chỉ dời theo hướng có lợi)
   if(isBuy)
   {
      if(candidate > currentSL + _Point * 0.5 && candidate < tick.bid)
         return candidate;
   }
   else
   {
      if((currentSL <= 0.0 || candidate < currentSL - _Point * 0.5) && candidate > tick.ask)
         return candidate;
   }
   return currentSL;
}

//+------------------------------------------------------------------+
//| Hàm tương thích sự kiện Timer (Ủy quyền cho Trọng tài xử lý)     |
//+------------------------------------------------------------------+
void ProcessAdvancedTrailing()
{
   // Trong kiến trúc v12, toàn bộ 9 kiểu Trailing được gom vào CSlTpVolumeArbiter
   // chạy trong ProcessCoreLogic() để tránh tuyệt đối việc 2 hàm cùng sửa SL gây xung đột.
   // Hàm này chỉ kiểm tra làm mới Handle chỉ báo khi cần thiết.
   if(g_advTrailMode != ADV_TRAIL_OFF)
      EnsureAdvancedTrailHandle();
}
// ============================================================================
// MODULE 5: CPartialMatrixEngine (MA TRẬN 10 CẤP PARTIAL TP & 10 CẤP PARTIAL SL)
// ============================================================================

//+------------------------------------------------------------------+
//| Kiểm tra ma trận 10 cấp Partial TP và thực thi đóng từng phần    |
//+------------------------------------------------------------------+
void ProcessPartialTpMatrix(ulong ticket, long posId, bool isBuy, double entry, double oneR,
                            double currentR, double currentVol, double &actualClosedSum)
    {
    actualClosedSum = 0.0;
    if(!g_enPartial || oneR <= 0.0 || currentVol <= 0.0)
        return;

    string maskKey = AccountScopedGV("PTPMASK_" + IntegerToString(posId));
    string execSym = GetExecutionSymbol();
    double minLot  = SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN);
    double lotStep = SymbolInfoDouble(execSym, SYMBOL_VOLUME_STEP);
    if(lotStep <= 0.0) lotStep = 0.01;
    int digits     = GetStepDigits(lotStep);

    MqlTick tick;
    if(!SymbolInfoTick(execSym, tick))
        return;
    double livePx = isBuy ? tick.bid : tick.ask;

    // Lấy khối lượng gốc ban đầu của vị thế (Initial Volume)
    string initVolKey = InitialVolKey(posId);
    double initialVol = GlobalVariableCheck(initVolKey) ? GlobalVariableGet(initVolKey) : currentVol;
    if(!GlobalVariableCheck(initVolKey) && currentVol > 0.0)
        {
        GlobalVariableSet(initVolKey, currentVol);
        initialVol = currentVol;
        }

    for(int t = 0; t < 10; t++)
        {
        if(!g_tpTiers[t].enabled || IsTierBitSet(maskKey, t))
            continue;

        // Tính mức giá kích hoạt của tầng t
        double trigPrice = 0.0;
        bool   reached   = false;
        double vVal      = g_tpTiers[t].triggerVal;

        switch(g_tpTiers[t].triggerUnit)
            {
            case UNIT_RR:
                trigPrice = entry + (isBuy ? 1.0 : -1.0) * (oneR * vVal);
                reached   = (currentR >= vVal - 1e-6);
                break;
            case UNIT_PIPS_POINTS:
                trigPrice = entry + (isBuy ? 1.0 : -1.0) * (vVal * _Point);
                reached   = isBuy ? (livePx >= trigPrice - _Point * 0.1) : (livePx <= trigPrice + _Point * 0.1);
                break;
            case UNIT_PCT_OF_TP:
            {
                // Lấy TP tổng từ vị thế hoặc tính theo R:R mục tiêu
                double finalTp = PositionGetDouble(POSITION_TP);
                if(finalTp <= 0.0)
                    finalTp = entry + (isBuy ? 1.0 : -1.0) * (oneR * g_targetRR);
                double totalDist = MathAbs(finalTp - entry);
                if(totalDist > _Point)
                {
                    trigPrice = entry + (isBuy ? 1.0 : -1.0) * (totalDist * (vVal / 100.0));
                    double curDist = isBuy ? (livePx - entry) : (entry - livePx);
                    reached   = ((curDist / totalDist) * 100.0 >= vVal - 1e-4);
                }
                break;
            }
            case UNIT_PRICE:
                trigPrice = vVal;
                reached   = isBuy ? (livePx >= trigPrice - _Point * 0.1) : (livePx <= trigPrice + _Point * 0.1);
                break;
            }

        if(!reached)
            continue;

        // Tính khối lượng cần cắt của tầng t
        double targetCloseVol = 0.0;
        if(g_tpTiers[t].volMode == VOL_PCT_INITIAL)
            targetCloseVol = initialVol * (g_tpTiers[t].closePct / 100.0);
        else
            targetCloseVol = currentVol * (g_tpTiers[t].closePct / 100.0);

        targetCloseVol = FloorLotStep(targetCloseVol);

        // Bảo toàn ràng buộc sàn: nếu đây là tầng cuối hoặc phần còn lại < minLot, gom luôn toàn bộ
        bool isLastActiveTier = true;
        for(int rest = t + 1; rest < 10; rest++)
            {
            if(g_tpTiers[rest].enabled && !IsTierBitSet(maskKey, rest))
                { isLastActiveTier = false; break; }
            }
        if(isLastActiveTier || currentVol - targetCloseVol < minLot - 1e-6)
            targetCloseVol = currentVol;

        if(targetCloseVol < minLot)
            {
            // Tích lũy tỷ lệ sang tầng kế tiếp nếu lot quá nhỏ
            continue;
            }

        double closedNow = 0.0;
        if(ClosePositionPartiallyByTicket(ticket, targetCloseVol, closedNow))
            {
            actualClosedSum += closedNow;
            currentVol      = MathMax(0.0, currentVol - closedNow);
            SetTierBit(maskKey, t);
            Alert(StringFormat("TradeDesk TP Tầng %d: Đã chốt %.2f lot tại ngưỡng %.2f (R: %.2f)",
                               t + 1, closedNow, trigPrice, currentR));
            if(currentVol < minLot)
                break;
            }
        }
}

//+------------------------------------------------------------------+
//| Kiểm tra ma trận 10 cấp Partial SL và thực thi cắt lỗ từng phần  |
//+------------------------------------------------------------------+
void ProcessPartialSlMatrix(ulong ticket, long posId, bool isBuy, double entry, double oneR,
                            double currentR, double currentVol, double &actualClosedSum)
{
   actualClosedSum = 0.0;
   if(!g_enPartialSL || oneR <= 0.0 || currentVol <= 0.0)
      return;

   string maskKey = AccountScopedGV("PSLMASK_" + IntegerToString(posId));
   string execSym = GetExecutionSymbol();
   double minLot  = SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN);

   MqlTick tick;
   if(!SymbolInfoTick(execSym, tick))
      return;
   double livePx = isBuy ? tick.bid : tick.ask;

   string initVolKey = InitialVolKey(posId);
   double initialVol = GlobalVariableCheck(initVolKey) ? GlobalVariableGet(initVolKey) : currentVol;

   for(int m = 0; m < 10; m++)
   {
      if(!g_slTiers[m].enabled || IsTierBitSet(maskKey, m))
         continue;

      double vVal   = g_slTiers[m].triggerVal;
      bool   reached = false;

      switch(g_slTiers[m].triggerUnit)
      {
         case UNIT_RR:
            // Partial SL xét khi giá đi âm (currentR <= -vVal, ví dụ -0.25R, -0.50R)
            reached = (currentR <= -vVal + 1e-6);
            break;
         case UNIT_PIPS_POINTS:
         {
            double lossPts = isBuy ? (entry - livePx) : (livePx - entry);
            reached = (lossPts >= vVal);
            break;
         }
         case UNIT_PCT_OF_TP:
         {
            // [v12.1] % quãng đường Entry->TP tổng, đo theo chiều BẤT LỢI (giá đi ngược vị thế)
            double finalTp = 0.0;
            if(PositionSelectByTicket(ticket))
               finalTp = PositionGetDouble(POSITION_TP);
            if(finalTp <= 0.0)
               finalTp = entry + (isBuy ? 1.0 : -1.0) * (oneR * g_targetRR);
            double totalDist = MathAbs(finalTp - entry);
            if(totalDist > ExecPoint())
            {
               double lossDist = isBuy ? (entry - livePx) : (livePx - entry);
               reached = (lossDist > 0.0 && (lossDist / totalDist) * 100.0 >= vVal - 1e-4);
            }
            break;
         }
         case UNIT_PRICE:
            reached = isBuy ? (livePx <= vVal + ExecPoint() * 0.1) : (livePx >= vVal - ExecPoint() * 0.1);
            break;
         default:
            break;
      }

      if(!reached)
         continue;

      double targetCloseVol = 0.0;
      if(g_slTiers[m].volMode == VOL_PCT_INITIAL)
         targetCloseVol = initialVol * (g_slTiers[m].closePct / 100.0);
      else
         targetCloseVol = currentVol * (g_slTiers[m].closePct / 100.0);

      targetCloseVol = FloorLotStep(targetCloseVol);

      bool isLastSlTier = true;
      for(int rest = m + 1; rest < 10; rest++)
      {
         if(g_slTiers[rest].enabled && !IsTierBitSet(maskKey, rest))
            { isLastSlTier = false; break; }
      }
      if(isLastSlTier || currentVol - targetCloseVol < minLot - 1e-6)
         targetCloseVol = currentVol;

      if(targetCloseVol < minLot)
         continue;

      double closedNow = 0.0;
      if(ClosePositionPartiallyByTicket(ticket, targetCloseVol, closedNow))
      {
         actualClosedSum += closedNow;
         currentVol      = MathMax(0.0, currentVol - closedNow);
         SetTierBit(maskKey, m);
         Alert(StringFormat("TradeDesk SL Tầng %d: Cắt lỗ từng phần %.2f lot tại mức R: %.2f",
                            m + 1, closedNow, currentR));
         if(currentVol < minLot)
            break;
      }
   }
}

// ============================================================================
// MODULE 9: CSlTpVolumeArbiter (BỘ TRỌNG TÀI ĐỘC QUYỀN ĐIỀU PHỐI LỆNH)
// ============================================================================

//+------------------------------------------------------------------+
//| Bộ Trọng tài Trung tâm: Giải quyết Mọi Xung đột Ghi đè SL/TP      |
//+------------------------------------------------------------------+
void ExecuteArbiterDecision(const SArbiterDecision &dec)
{
   if(dec.ticket == 0 && dec.positionId == 0)
      return;

   // Ưu tiên P1: Đóng cưỡng bức toàn phần (Force Flatten)
   if(dec.forceCloseFull)
   {
      ClosePositionWithConfirmation(dec.ticket);
      return;
   }

   // Ưu tiên P3(T2) & P4: Cắt một phần khối lượng từ Partial TP hoặc Partial SL
   if(dec.partialCloseVol > 0.0)
   {
      ClosePositionPartiallyByTicket(dec.ticket, dec.partialCloseVol);
   }

   // Đọc thông tin vị thế hiện tại để kiểm tra luật bánh cóc đơn điệu (Monotonic Ratchet)
   if(!PositionSelectByTicket(dec.ticket))
      return;

   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   bool   isBuy     = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   string execSym   = PositionGetString(POSITION_SYMBOL);

   // Nếu vị thế đang bật SL Ảo (Virtual SL), ưu tiên cập nhật mức V-SL trong GV
   string vslKey = VirtualSLPositionKey(dec.positionId);
   if(GlobalVariableCheck(vslKey))
   {
      double savedVsl = GlobalVariableGet(vslKey);
      if(dec.candidateSL > 0.0)
      {
         bool tighter = isBuy ? (dec.candidateSL > savedVsl + _Point * 0.5)
                              : (savedVsl <= 0.0 || dec.candidateSL < savedVsl - _Point * 0.5);
         if(savedVsl <= 0.0 || tighter)
            GlobalVariableSet(vslKey, dec.candidateSL);
      }
      string emgKey = VirtualEmergencySLPositionKey(dec.positionId);
      double actualBrokerSl = PositionGetDouble(POSITION_SL);
      double savedEmg = GlobalVariableCheck(emgKey) ? GlobalVariableGet(emgKey) : actualBrokerSl;
      if(isBuy ? (actualBrokerSl > savedEmg + _Point * 0.5) : (actualBrokerSl > 0.0 && actualBrokerSl < savedEmg - _Point * 0.5))
      {
         savedEmg = actualBrokerSl;
         GlobalVariableSet(emgKey, savedEmg);
      }
      // Khi dùng SL ảo, SL thực gửi lên broker giữ ở mức khẩn cấp (Emergency SL)
      if(savedEmg > 0.0)
         currentSL = savedEmg;
   }

   // Kiểm tra gỡ Hard TP trên máy chủ khi xung đột với Partial TP
   double targetTP = currentTP;
   if(dec.suppressHardTp)
      targetTP = 0.0;
   else if(dec.candidateTP > 0.0)
      targetTP = dec.candidateTP;

   // Kiểm tra luật đơn điệu cho Stop Loss
   double targetSL = currentSL;
   if(g_trailStyle == TRAIL_STYLE_MANUAL_SL)
   {
      // SL tay 100%: Tuyệt đối không tự dời SL, trừ khi gắn khởi tạo ban đầu
      if(dec.attachInitLevels && currentSL <= 0.0 && dec.candidateSL > 0.0)
         targetSL = dec.candidateSL;
   }
   else if(dec.candidateSL > 0.0)
   {
      double tickSize = SymbolInfoDouble(execSym, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0) tickSize = _Point;

      if(isBuy)
      {
         if(dec.candidateSL > currentSL + tickSize * 0.5)
            targetSL = dec.candidateSL;
      }
      else
      {
         if(currentSL <= 0.0 || dec.candidateSL < currentSL - tickSize * 0.5)
            targetSL = dec.candidateSL;
      }
   }

   // Kiểm tra vùng Stops Level và Freeze Level của sàn trước khi gửi
   string valReason = "";
   if((MathAbs(targetSL - currentSL) > _Point * 0.5 || MathAbs(targetTP - currentTP) > _Point * 0.5))
   {
      double testSl = targetSL, testTp = targetTP;
      if(ValidateStopsForModify(dec.ticket, testSl, testTp, valReason))
      {
         ModifyPositionWithConfirmation(dec.ticket, testSl, testTp);
      }
   }
}
// ============================================================================
// PHẦN PHỤ TRỢ THỰC THI LỆNH, XÁC NHẬN BROKER & ĐÓNG NHÓM ASYNC (TRADE OPS)
// ============================================================================

//+------------------------------------------------------------------+
//| Kiểm tra kết quả trả về từ CTrade có được máy chủ chấp nhận không |
//+------------------------------------------------------------------+
bool TradeRequestSucceeded(bool requestSent)
{
   if(!requestSent)
      return false;
   uint retcode = trade.ResultRetcode();
   return (retcode == TRADE_RETCODE_DONE ||
           retcode == TRADE_RETCODE_DONE_PARTIAL ||
           retcode == TRADE_RETCODE_PLACED ||
           retcode == TRADE_RETCODE_NO_CHANGES);
}

//+------------------------------------------------------------------+
//| Cấu hình Filling Mode tự động tương thích mọi sàn (FOK/IOC/RET)  |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING ResolveSymbolFillingMode(string symbol)
{
   uint filling = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) != 0)
      return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Kiểm tra lịch sử vị thế để khôi phục cờ chốt từng phần sau Restart|
//+------------------------------------------------------------------+
bool PreparePositionPartialState(long positionId, string partialStateKey)
{
   if(positionId <= 0)
      return false;

   string reviewedKey = AccountScopedGV("EAP85_HISTCHECK_" + IntegerToString(positionId));
   if(GlobalVariableCheck(reviewedKey))
      return true;

   if(!HistorySelectByPosition((ulong)positionId))
      return false; // Thử lại ở chu kỳ sau khi MT5 đã đồng bộ lịch sử của vị thế này

   int total = HistoryDealsTotal();
   bool foundClose = false;
   double initVol  = 0.0;
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || HistoryDealGetInteger(deal, DEAL_POSITION_ID) != positionId)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN && initVol <= 0.0)
         initVol = HistoryDealGetDouble(deal, DEAL_VOLUME);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
      {
         if(HistoryDealGetDouble(deal, DEAL_VOLUME) > 0.0)
            foundClose = true;
      }
   }
   if(initVol > 0.0 && !GlobalVariableCheck(InitialVolKey(positionId)))
      GlobalVariableSet(InitialVolKey(positionId), initVol);

   GlobalVariableSet(reviewedKey, 1.0);
   if(foundClose)
   {
      GlobalVariableSet(partialStateKey, 1.0);
      SetTierBit(PartialTpMaskKey(positionId), 0);
   }
   return true;
}

//+------------------------------------------------------------------+
//| Kiểm tra điều kiện Stops Level & Freeze Level trước khi sửa SL/TP|
//+------------------------------------------------------------------+
bool ValidateStopsForModify(ulong ticket, double &sl, double &tp, string &reason)
{
   reason = "";
   if(!PositionSelectByTicket(ticket))
   {
      reason = "không tìm thấy vị thế";
      return false;
   }

   string symbol    = PositionGetString(POSITION_SYMBOL);
   long   type      = PositionGetInteger(POSITION_TYPE);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0)
      tickSize = point;
   if(point <= 0.0 || tickSize <= 0.0)
   {
      reason = "không đọc được bước giá của mã";
      return false;
   }

   if(sl > 0.0)
      sl = NormalizePriceToTickSize(symbol, sl);
   if(tp > 0.0)
      tp = NormalizePriceToTickSize(symbol, tp);

   double tolerance = tickSize * 0.5;
   bool slChanged = (sl > 0.0 && (currentSL <= 0.0 || MathAbs(sl - currentSL) > tolerance)) ||
                    (sl == 0.0 && currentSL > 0.0);
   bool tpChanged = (tp > 0.0 && (currentTP <= 0.0 || MathAbs(tp - currentTP) > tolerance)) ||
                    (tp == 0.0 && currentTP > 0.0);
   if(!slChanged && !tpChanged)
      return true;

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
   {
      reason = "không đọc được giá Bid/Ask mới nhất";
      return false;
   }

   long stopsLevel  = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minGap    = (double)MathMax(stopsLevel, freezeLevel) * point;
   double eps       = point * 0.1;

   if(slChanged && sl > 0.0)
   {
      if(type == POSITION_TYPE_BUY)
      {
         if(sl >= tick.bid - eps || tick.bid - sl + eps < minGap)
         {
            reason = "SL mua nằm trong khoảng Stops/Freeze của sàn";
            return false;
         }
      }
      else if(sl <= tick.ask + eps || sl - tick.ask + eps < minGap)
      {
         reason = "SL bán nằm trong khoảng Stops/Freeze của sàn";
         return false;
      }
   }

   if(tpChanged && tp > 0.0)
   {
      if(type == POSITION_TYPE_BUY)
      {
         if(tp <= tick.ask + eps || tp - tick.ask + eps < minGap)
         {
            reason = "TP mua nằm trong khoảng Stops/Freeze của sàn";
            return false;
         }
      }
      else if(tp >= tick.bid - eps || tick.bid - tp + eps < minGap)
      {
         reason = "TP bán nằm trong khoảng Stops/Freeze của sàn";
         return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Sửa SL/TP vị thế có xác nhận, đồng bộ tự động với Virtual SL/TP  |
//+------------------------------------------------------------------+
bool ModifyPositionWithConfirmation(ulong ticket, double sl, double tp)
{
   if(PositionSelectByTicket(ticket))
   {
      long   posId      = PositionGetInteger(POSITION_IDENTIFIER);
      long   posType    = PositionGetInteger(POSITION_TYPE);
      string posSymbol  = PositionGetString(POSITION_SYMBOL);
      double posEntry   = PositionGetDouble(POSITION_PRICE_OPEN);

      // Nếu vị thế đang bật TP ảo, giữ TP ảo trong GV và gửi TP = 0.0 lên máy chủ
      string virtualTpKey = VirtualTPPositionKey(posId);
      if(GlobalVariableCheck(virtualTpKey))
      {
         if(tp > 0.0)
            GlobalVariableSet(virtualTpKey, NormalizePriceToTickSize(posSymbol, tp));
         tp = 0.0;
      }

      // Nếu vị thế đang bật SL ảo, cập nhật SL ảo và kéo theo Emergency Server SL
      string virtualSlKey = VirtualSLPositionKey(posId);
      if(GlobalVariableCheck(virtualSlKey))
      {
         double desiredSL = sl;
         double savedSL   = GlobalVariableGet(virtualSlKey);
         if(desiredSL > 0.0)
         {
            desiredSL = NormalizePriceToTickSize(posSymbol, desiredSL);
            bool tighter = (posType == POSITION_TYPE_BUY)
                           ? (desiredSL > savedSL + _Point * 0.5)
                           : (savedSL <= 0.0 || desiredSL < savedSL - _Point * 0.5);
            if(savedSL <= 0.0 || tighter)
            {
               GlobalVariableSet(virtualSlKey, desiredSL);
               savedSL = desiredSL;
            }
         }

         string emergencyKey   = VirtualEmergencySLPositionKey(posId);
         double emergencySL    = GlobalVariableCheck(emergencyKey) ? GlobalVariableGet(emergencyKey) : PositionGetDouble(POSITION_SL);
         double actualBrokerSL = PositionGetDouble(POSITION_SL);

         // Kéo theo SL khẩn cấp trên broker khi SL ảo dịch chuyển có lợi
         if(InpEnableEmergencyServerSL && savedSL > 0.0 && posEntry > 0.0)
         {
            string gv1R = AccountScopedGV("EAP82_1R_" + IntegerToString(posId));
            double baseDist = GlobalVariableCheck(gv1R) ? GlobalVariableGet(gv1R) : MathAbs(posEntry - savedSL);
            double emgGap   = MathMax(_Point * 20, baseDist * MathMax(0.25, InpEmergencySLMultiplier - 1.0));
            double trailedEmg = (posType == POSITION_TYPE_BUY)
                                ? NormalizePriceToTickSize(posSymbol, savedSL - emgGap)
                                : NormalizePriceToTickSize(posSymbol, savedSL + emgGap);
            bool emgTighter = (posType == POSITION_TYPE_BUY)
                              ? (trailedEmg > emergencySL + _Point * 0.5)
                              : (emergencySL <= 0.0 || trailedEmg < emergencySL - _Point * 0.5);
            if(emgTighter)
            {
               emergencySL = trailedEmg;
               GlobalVariableSet(emergencyKey, emergencySL);
            }
         }

         bool brokerStopWasTightened = (posType == POSITION_TYPE_BUY)
                                       ? (actualBrokerSL > 0.0 && emergencySL > 0.0 && actualBrokerSL > emergencySL + _Point * 0.5)
                                       : (actualBrokerSL > 0.0 && emergencySL > 0.0 && actualBrokerSL < emergencySL - _Point * 0.5);
         if(brokerStopWasTightened)
         {
            emergencySL = actualBrokerSL;
            GlobalVariableSet(emergencyKey, emergencySL);
         }

         if(!InpEnableEmergencyServerSL)
            sl = 0.0;
         else if(emergencySL > 0.0)
            sl = emergencySL;
         else
            sl = actualBrokerSL;
      }
   }

   string warnKey = AccountScopedGV("EAP82_MODWARN_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + IntegerToString((long)ticket));
   string validationReason = "";
   if(!ValidateStopsForModify(ticket, sl, tp, validationReason))
   {
      datetime now = TimeLocal();
      datetime lastWarning = GlobalVariableCheck(warnKey) ? (datetime)GlobalVariableGet(warnKey) : 0;
      if(lastWarning == 0 || now - lastWarning >= 60)
      {
         Print("TuanProtrade: Tạm hoãn sửa SL/TP vị thế #", ticket, " (", validationReason, "). Sẽ tự động áp dụng khi giá giãn ra.");
         GlobalVariableSet(warnKey, (double)now);
      }
      return false;
   }

   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);
   if(MathAbs(sl - curSL) <= _Point * 0.2 && MathAbs(tp - curTP) <= _Point * 0.2)
      return true;

   bool succeeded = TradeRequestSucceeded(trade.PositionModify(ticket, sl, tp));
   if(succeeded)
   {
      GlobalVariableDel(warnKey);
      return true;
   }

   datetime now = TimeLocal();
   datetime lastWarning = GlobalVariableCheck(warnKey) ? (datetime)GlobalVariableGet(warnKey) : 0;
   if(lastWarning == 0 || now - lastWarning >= 60)
   {
      Print("TuanProtrade: Sửa SL/TP vị thế #", ticket, " chưa được máy chủ xác nhận. Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      GlobalVariableSet(warnKey, (double)now);
   }
   return false;
}

//+------------------------------------------------------------------+
//| Đóng vị thế có xác nhận và cơ chế chống gửi lặp (Backoff 2 giây) |
//+------------------------------------------------------------------+
bool ClosePositionWithConfirmation(ulong ticket)
{
   string accountKey = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + IntegerToString((long)ticket);
   string tryKey     = AccountScopedGV("EAP82_CLOSETRY_"  + accountKey);
   string warnKey    = AccountScopedGV("EAP82_CLOSEWARN_" + accountKey);
   if(!PositionSelectByTicket(ticket))
   {
      GlobalVariableDel(tryKey);
      GlobalVariableDel(warnKey);
      return true;
   }
   datetime now = TimeLocal();
   datetime lastTry = GlobalVariableCheck(tryKey) ? (datetime)GlobalVariableGet(tryKey) : 0;
   if(lastTry > 0 && now - lastTry < 2)
      return false;
   GlobalVariableSet(tryKey, (double)now);

   string posSym = PositionGetString(POSITION_SYMBOL);
   trade.SetTypeFillingBySymbol(posSym);
   bool requestAccepted = TradeRequestSucceeded(trade.PositionClose(ticket));
   if(requestAccepted && !PositionSelectByTicket(ticket))
   {
      GlobalVariableDel(tryKey);
      GlobalVariableDel(warnKey);
      return true;
   }

   datetime lastWarning = GlobalVariableCheck(warnKey) ? (datetime)GlobalVariableGet(warnKey) : 0;
   if(lastWarning == 0 || now - lastWarning >= 60)
   {
      Print("TuanProtrade: Đóng vị thế #", ticket,
            requestAccepted ? " mới khớp một phần; EA sẽ thử tiếp." : " chưa được máy chủ xác nhận. Retcode=",
            trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      GlobalVariableSet(warnKey, (double)now);
   }
   return false;
}

//+------------------------------------------------------------------+
//| Gửi lệnh đóng bất đồng bộ tốc độ cao (OrderSendAsync Batching)   |
//+------------------------------------------------------------------+
bool SendAsyncPositionClose(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return true;

   string symbol = PositionGetString(POSITION_SYMBOL);
   double volume = PositionGetDouble(POSITION_VOLUME);
   long   type   = PositionGetInteger(POSITION_TYPE);
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
      return false;

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action       = TRADE_ACTION_DEAL;
   req.position     = ticket;
   req.symbol       = symbol;
   req.volume       = volume;
   req.type         = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.price        = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
   req.deviation    = (ulong)MathMax(10, InpMaxDeviationPoints);
   req.magic        = (ulong)InpTradeMagicNumber;
   req.type_filling = ResolveSymbolFillingMode(symbol);
   req.comment      = "TradeDesk Async Close";

   return OrderSendAsync(req, res);
}

//+------------------------------------------------------------------+
//| Đóng một phần khối lượng vị thế (Hỗ trợ cả Hedging & Netting)    |
//+------------------------------------------------------------------+
void ReportPartialTPIssue(long positionId, string message)
{
   string warnKey = AccountScopedGV("EAP82_PARTWARN_" + IntegerToString(positionId));
   datetime now = TimeCurrent();
   datetime lastWarning = GlobalVariableCheck(warnKey) ? (datetime)GlobalVariableGet(warnKey) : 0;
   if(lastWarning == 0 || now - lastWarning >= 60)
   {
      Print("TuanProtrade Partial | Position #", positionId, ": ", message);
      GlobalVariableSet(warnKey, (double)now);
   }
}

bool ClosePositionPartiallyByTicket(ulong ticket, double requestedVolume, double &actualClosedVolume)
{
   actualClosedVolume = 0.0;
   if(!PositionSelectByTicket(ticket))
      return false;

   string symbol  = PositionGetString(POSITION_SYMBOL);
   string execSym = GetExecutionSymbol();
   if(symbol != _Symbol && symbol != execSym)
      return false;

   double volumeBefore = PositionGetDouble(POSITION_VOLUME);
   double minVolume    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double step         = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   int digits          = GetStepDigits(step);

   // Nếu yêu cầu đóng >= toàn bộ khối lượng hiện có, chuyển sang đóng hoàn toàn
   if(requestedVolume >= volumeBefore - minVolume + 1e-8)
   {
      if(ClosePositionWithConfirmation(ticket))
      {
         actualClosedVolume = volumeBefore;
         return true;
      }
      return false;
   }

   double closeVolume = MathFloor((MathMin(requestedVolume, volumeBefore - minVolume) + step * 1e-9) / step) * step;
   closeVolume = NormalizeDouble(closeVolume, digits);
   if(closeVolume < minVolume || volumeBefore - closeVolume < minVolume - 1e-8)
      return false;

   trade.SetTypeFillingBySymbol(symbol);
   bool requestSent = false;
   ENUM_ACCOUNT_MARGIN_MODE marginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      requestSent = trade.PositionClosePartial(ticket, closeVolume);
   }
   else
   {
      // Trên tài khoản Netting: kiểm tra chặt chẽ trước khi gửi lệnh đối ứng để không đảo chiều vị thế
      long positionType = PositionGetInteger(POSITION_TYPE);
      if(positionType == POSITION_TYPE_BUY)
         requestSent = trade.Sell(closeVolume, symbol, 0.0, 0.0, 0.0, "TuanProtrade Partial Close");
      else
         requestSent = trade.Buy(closeVolume, symbol, 0.0, 0.0, 0.0, "TuanProtrade Partial Close");
   }
   if(!TradeRequestSucceeded(requestSent))
      return false;

   if(PositionSelectByTicket(ticket))
      actualClosedVolume = MathMax(0.0, volumeBefore - PositionGetDouble(POSITION_VOLUME));
   else
      actualClosedVolume = volumeBefore;
   return (actualClosedVolume > 0.0);
}

bool ClosePositionPartiallyByTicket(ulong ticket, double requestedVolume)
{
   double actualClosedVolume = 0.0;
   if(!ClosePositionPartiallyByTicket(ticket, requestedVolume, actualClosedVolume))
      return false;
   double step = SymbolInfoDouble(GetExecutionSymbol(), SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   return (actualClosedVolume + step * 0.5 >= requestedVolume);
}

bool CloseExternalPositionPartially(ulong ticket, double requested, double &closed)
{
   closed = 0.0;
   if(!PositionSelectByTicket(ticket) || requested <= 0.0)
      return false;
   string symbol = PositionGetString(POSITION_SYMBOL);
   double before = PositionGetDouble(POSITION_VOLUME);
   double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   if(step <= 0.0) step = 0.01;
   int digits = GetStepDigits(step);
   double amount = MathFloor((requested + step * 1e-9) / step) * step;
   amount = NormalizeDouble(MathMin(amount, before - minLot), digits);
   if(amount < minLot || before - amount < minLot - step * 0.5)
      return false;

   trade.SetTypeFillingBySymbol(symbol);
   bool sent = false;
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      sent = trade.PositionClosePartial(ticket, amount);
   else
   {
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      sent = isBuy ? trade.Sell(amount, symbol, 0.0, 0.0, 0.0, "TradeDesk external risk trim")
                   : trade.Buy(amount, symbol, 0.0, 0.0, 0.0, "TradeDesk external risk trim");
   }
   if(!TradeRequestSucceeded(sent))
      return false;
   if(PositionSelectByTicket(ticket))
      closed = MathMax(0.0, before - PositionGetDouble(POSITION_VOLUME));
   else
      closed = before;
   return (closed > 0.0);
}

//+------------------------------------------------------------------+
//| Xóa lệnh chờ có xác nhận từ máy chủ                              |
//+------------------------------------------------------------------+
bool DeleteOrderWithConfirmation(ulong ticket)
{
   string accountKey = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + IntegerToString((long)ticket);
   string tryKey     = AccountScopedGV("EAP82_ORDERTRY_"  + accountKey);
   string warnKey    = AccountScopedGV("EAP82_ORDERWARN_" + accountKey);
   if(!OrderSelect(ticket))
   {
      GlobalVariableDel(tryKey);
      GlobalVariableDel(warnKey);
      return true;
   }
   datetime now = TimeLocal();
   datetime lastTry = GlobalVariableCheck(tryKey) ? (datetime)GlobalVariableGet(tryKey) : 0;
   if(lastTry > 0 && now - lastTry < 2)
      return false;
   GlobalVariableSet(tryKey, (double)now);

   if(TradeRequestSucceeded(trade.OrderDelete(ticket)))
   {
      if(!OrderSelect(ticket))
      {
         GlobalVariableDel(tryKey);
         GlobalVariableDel(warnKey);
         return true;
      }
   }

   datetime lastWarning = GlobalVariableCheck(warnKey) ? (datetime)GlobalVariableGet(warnKey) : 0;
   if(lastWarning == 0 || now - lastWarning >= 60)
   {
      Print("TuanProtrade: Xóa lệnh chờ #", ticket, " chưa được máy chủ xác nhận. Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      GlobalVariableSet(warnKey, (double)now);
   }
   return false;
}

//+------------------------------------------------------------------+
//| Các hàm kiểm tra và đóng vị thế theo phạm vi (Symbol / Toàn TK)  |
//+------------------------------------------------------------------+
bool CloseAllPositionsOnChartSymbol()
{
   string execSym = GetExecutionSymbol();
   bool hadPosition = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string s = PositionGetString(POSITION_SYMBOL);
      if(s != _Symbol && s != execSym) continue;
      hadPosition = true;
      ClosePositionWithConfirmation(ticket);
   }
   if(!hadPosition)
      return true;
   for(int j = PositionsTotal() - 1; j >= 0; j--)
   {
      ulong ticket = PositionGetTicket(j);
      if(ticket == 0) continue;
      string s = PositionGetString(POSITION_SYMBOL);
      if(s == _Symbol || s == execSym)
         return false;
   }
   return true;
}

void CloseAllTradesAndOrders(string reason, bool accountWide)
{
   string execSym = GetExecutionSymbol();
   int attempted = 0, failed = 0;

   // TUANPROTRADE SAFETY: no mixed OrderSendAsync + synchronous close.
   // Mixing requests on the same ticket can result in duplicate netting reversals.
   // Forced liquidation always uses CTrade confirmation and retries on each timer.
   // Bước 2: Kiểm tra và xác nhận đóng từng vị thế còn sót
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string s = PositionGetString(POSITION_SYMBOL);
      if(!accountWide && s != _Symbol && s != execSym)
         continue;
      attempted++;
      if(!ClosePositionWithConfirmation(ticket))
         failed++;
   }

   // Bước 3: Hủy toàn bộ lệnh chờ trong phạm vi
   for(int j = OrdersTotal() - 1; j >= 0; j--)
   {
      ulong ordTicket = OrderGetTicket(j);
      if(ordTicket == 0) continue;
      string s = OrderGetString(ORDER_SYMBOL);
      if(!accountWide && s != _Symbol && s != execSym)
         continue;
      attempted++;
      if(!DeleteOrderWithConfirmation(ordTicket))
         failed++;
   }

   if(attempted > 0 && failed > 0)
   {
      datetime now = TimeLocal();
      if(g_lastBulkCloseWarning == 0 || now - g_lastBulkCloseWarning >= 60)
      {
         Print("TuanProtrade [ĐÓNG LỆNH] ", accountWide ? "toàn tài khoản" : _Symbol, ": ", reason,
               " | yêu cầu=", attempted, " | đang chờ xác nhận=", failed);
         g_lastBulkCloseWarning = now;
      }
   }
   SetToastStatus("Đã gửi yêu cầu đóng lệnh (" + reason + ")");
}

void ClosePositionsByFilter(bool winnersOnly, bool losersOnly, int sideFilter, bool accountWide)
{
   string execSym = GetExecutionSymbol();
   int attempted = 0, failed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      if(!accountWide && sym != _Symbol && sym != execSym) continue;
      long side = PositionGetInteger(POSITION_TYPE);
      if(sideFilter >= 0 && side != sideFilter) continue;
      double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(winnersOnly && pnl <= 0.0) continue;
      if(losersOnly  && pnl >= 0.0) continue;
      attempted++;
      if(InpEnableAsyncGroupClose)
         SendAsyncPositionClose(ticket);
      if(!ClosePositionWithConfirmation(ticket))
         failed++;
   }
   string msg = StringFormat("Đóng nhóm đã gửi %d lệnh; chờ xác nhận: %d", attempted, failed);
   SetToastStatus(msg);
   Alert("TuanProtrade: " + msg);
}

bool HasTradesInScope(bool accountWide)
{
   string execSym = GetExecutionSymbol();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string s = PositionGetString(POSITION_SYMBOL);
      if(accountWide || s == _Symbol || s == execSym)
         return true;
   }
   for(int j = OrdersTotal() - 1; j >= 0; j--)
   {
      ulong ticket = OrderGetTicket(j);
      if(ticket == 0) continue;
      string s = OrderGetString(ORDER_SYMBOL);
      if(accountWide || s == _Symbol || s == execSym)
         return true;
   }
   return false;
}

int CountPositionsInScope(bool accountWide)
{
   string execSym = GetExecutionSymbol();
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string s = PositionGetString(POSITION_SYMBOL);
      if(accountWide || s == _Symbol || s == execSym)
         count++;
   }
   return count;
}

// ============================================================================
// MODULE 6: CAdvancedOrderEngine (STOP-LIMIT, LPO, OCO 4 CHẾ ĐỘ, TRAIL PENDING)
// ============================================================================

//+------------------------------------------------------------------+
//| Cổng kiểm tra an toàn trước khi mở bất kỳ lệnh mới nào           |
//+------------------------------------------------------------------+
bool TradeDeskEntryGate(string &reason)
{
   reason = "";
   if(g_accountSwitchHold) { reason = "Tài khoản/server chưa được xác nhận"; return false; }
   if(g_manualForceLock)   { reason = "EA đang khóa thủ công"; return false; }
   if(g_riskBreached)      { reason = "Risk Guard đang khóa tài khoản"; return false; }
   if(g_enRiskGuard && !g_riskDataAvailable) { reason = "Lịch sử Risk Guard chưa tải xong"; return false; }
   if(g_equityLatched ||
      (GlobalVariableCheck(EquityProtectKey("LOCK", true)) && GlobalVariableGet(EquityProtectKey("LOCK", true)) > 0.5) ||
      (GlobalVariableCheck(EquityProtectKey("FLATTEN", true)) && GlobalVariableGet(EquityProtectKey("FLATTEN", true)) > 0.5))
   { reason = "Equity Protect đang khóa/đang xử lý đóng lệnh"; return false; }
   if(g_enNewsFilter && g_newsLockedState)   { reason = "Đang trong khung giờ lọc tin tức"; return false; }
   if(g_inRecoveryMode && g_enHalfRiskRec && CountPositionsInScope(InpRiskControlScope == SCOPE_ACCOUNT) >= g_maxRecOrders)
   {
      reason = StringFormat("Chế độ Phục hồi chỉ cho phép tối đa %d lệnh mở cùng lúc", g_maxRecOrders);
      return false;
   }
   if(g_timeManagerOn)
   {
      int colon = StringFind(InpTimedFlattenServerTime, ":");
      if(colon > 0)
      {
         int hh = (int)StringToInteger(StringSubstr(InpTimedFlattenServerTime, 0, colon));
         int mm = (int)StringToInteger(StringSubstr(InpTimedFlattenServerTime, colon + 1));
         MqlDateTime t;
         TimeToStruct(TimeTradeServer(), t);
         if(hh >= 0 && hh <= 23 && mm >= 0 && mm <= 59 && t.hour * 60 + t.min >= hh * 60 + mm)
         {
            reason = "Đã qua giờ đóng lệnh cuối phiên theo Trade Time Manager";
            return false;
         }
      }
   }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      reason = "Hãy bật Algo Trading trên MT5 và cấp quyền giao dịch cho EA";
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Gửi lệnh nguyên bản Buy Stop Limit / Sell Stop Limit của MT5     |
//+------------------------------------------------------------------+
bool SendNativeStopLimitOrder(bool isBuy, double volume, double stopTriggerPrice, double limitExecPrice,
                              double sl, double tp, string comment, ulong &outOrderTicket)
{
   outOrderTicket = 0;
   string execSym = GetExecutionSymbol();
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action       = TRADE_ACTION_PENDING;
   req.symbol       = execSym;
   req.volume       = volume;
   req.type         = isBuy ? ORDER_TYPE_BUY_STOP_LIMIT : ORDER_TYPE_SELL_STOP_LIMIT;
   req.price        = NormalizePriceToTickSize(execSym, stopTriggerPrice);
   req.stoplimit    = NormalizePriceToTickSize(execSym, limitExecPrice);
   req.sl           = (sl > 0.0) ? NormalizePriceToTickSize(execSym, sl) : 0.0;
   req.tp           = (tp > 0.0) ? NormalizePriceToTickSize(execSym, tp) : 0.0;
   req.magic        = (ulong)InpTradeMagicNumber;
   req.type_filling = ResolveSymbolFillingMode(execSym);
   req.type_time    = ORDER_TIME_GTC;
   req.comment      = comment;

   bool sent = OrderSend(req, res);
   if(sent && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED))
   {
      outOrderTicket = res.order;
      return true;
   }
   Print("TradeDesk Stop-Limit Error: retcode=", res.retcode, " comment=", res.comment);
   return false;
}

//+------------------------------------------------------------------+
//| Đặt lệnh thủ công đa chế độ (Market, Limit, Stop, LPO, StopLimit)|
//+------------------------------------------------------------------+
void PlaceManualOrder(bool isBuy)
{
   string reason = "";
   if(!TradeDeskEntryGate(reason))
   {
      SetToastStatus("Từ chối lệnh: " + reason);
      Alert("TuanProtrade: ", reason);
      return;
   }

   // Nếu đang ở chế độ OCO (g_entryMode == ENTRY_MODE_OCO), chuyển sang đặt cặp OCO
   if(g_entryMode == ENTRY_MODE_OCO)
   {
      PlaceOcoBracket();
      return;
   }

   // Kiểm tra cảnh báo xu hướng từ Cầu nối Chỉ báo STTS (Copilot Mode)
   if(g_sttsBridgeMode == STTS_BRIDGE_FILTER_HUD && g_sttsCurrentTrend != 0)
   {
      if((isBuy && g_sttsCurrentTrend < 0) || (!isBuy && g_sttsCurrentTrend > 0))
      {
         int ans = MessageBox("CẢNH BÁO STTS COPILOT: Lệnh bạn vừa chọn ngược chiều với xu hướng chính của Smart Trend Trading System!\nBạn vẫn muốn tiếp tục gửi lệnh?",
                              "TuanProtrade - STTS Filter", MB_YESNO | MB_ICONWARNING);
         if(ans != IDYES)
            return;
      }
   }

   g_tradeSide = isBuy ? SIDE_LONG : SIDE_SHORT;
   ProcessCoreLogic();
   if(!TradeDeskEntryGate(reason))
   {
      Alert("TuanProtrade: ", reason);
      return;
   }

   // Nếu đang chọn LPO và bật chế độ LPO 2 pha chuẩn InvestSoft (InpLpoRequireVirtual),
   // đăng ký ngay vào Sổ Lệnh Chờ Ảo (Virtual Order Book) để chạy máy trạng thái 2 pha!
   if(g_entryMode == ENTRY_MODE_LPO && InpLpoRequireVirtual)
   {
      ArmOrCancelVirtualPending();
      RebuildCleanPanel(false);
      return;
   }

   string execSym = GetExecutionSymbol();
   MqlTick tick;
   if(!SymbolInfoTick(execSym, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
   {
      Alert("TuanProtrade: Không nhận được giá Bid/Ask hợp lệ trên ", execSym);
      return;
   }

   long stopsLvl  = SymbolInfoInteger(execSym, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLvl = SymbolInfoInteger(execSym, SYMBOL_TRADE_FREEZE_LEVEL);
   double minGap  = (double)MathMax(1, (int)MathMax(stopsLvl, freezeLvl) + 1) * _Point;

   double entry          = (g_entryMode == ENTRY_MODE_MARKET) ? (isBuy ? tick.ask : tick.bid) : g_sizerEntryPrice;
   double stopLimitExecP = entry;

   if(g_entryMode == ENTRY_MODE_LPO)
   {
      double pullback = MathMax(g_pullbackPoints * _Point, minGap);
      entry = isBuy ? (tick.ask - pullback) : (tick.bid + pullback);
   }
   else if(g_entryMode == ENTRY_MODE_STOP_LIMIT)
   {
      // Với Buy Stop Limit: entry (Stop Trigger) > Ask + minGap; stopLimitExecP <= entry
      if(isBuy && entry <= tick.ask + minGap)
         entry = NormalizePriceToTickSize(execSym, tick.ask + MathMax(minGap * 2.0, g_stopLimitOffsetPts * _Point));
      if(!isBuy && entry >= tick.bid - minGap)
         entry = NormalizePriceToTickSize(execSym, tick.bid - MathMax(minGap * 2.0, g_stopLimitOffsetPts * _Point));

      stopLimitExecP = (g_sizerStopLimitPrice > 0.0) ? g_sizerStopLimitPrice
                       : NormalizePriceToTickSize(execSym, entry + (isBuy ? -1.0 : 1.0) * g_stopLimitOffsetPts * _Point);
      if(isBuy && stopLimitExecP > entry)  stopLimitExecP = entry;
      if(!isBuy && stopLimitExecP < entry) stopLimitExecP = entry;
   }

   if(entry <= 0.0)
   {
      Alert("TuanProtrade: Giá Entry chưa hợp lệ.");
      return;
   }
   entry          = NormalizePriceToTickSize(execSym, entry);
   stopLimitExecP = NormalizePriceToTickSize(execSym, stopLimitExecP);

   double sizingEntryRef = (g_entryMode == ENTRY_MODE_STOP_LIMIT) ? stopLimitExecP : entry;
   double sl = 0.0, tp = 0.0;
   if(!GetEntryProtection(isBuy, sizingEntryRef, sl, tp))
   {
      Alert("TuanProtrade: Không tạo được SL/TP hợp lệ; hãy kiểm tra vị trí đường SL/TP.");
      return;
   }

   double serverSL = sl;
   if(g_virtualSLOn)
   {
      if(InpEnableEmergencyServerSL)
      {
         double slDistance = MathAbs(sizingEntryRef - sl);
         double emergencyMultiplier = MathMax(1.05, InpEmergencySLMultiplier);
         serverSL = NormalizePriceToTickSize(execSym, sizingEntryRef + (isBuy ? -1.0 : 1.0) * slDistance * emergencyMultiplier);
         if(serverSL <= 0.0 || (isBuy && serverSL >= sl) || (!isBuy && serverSL <= sl))
         {
            Alert("TuanProtrade: Không tạo được SL khẩn cấp hợp lệ.");
            return;
         }
      }
      else
         serverSL = 0.0;
   }

   if((g_entryMode == ENTRY_MODE_LIMIT || g_entryMode == ENTRY_MODE_LPO) &&
      ((isBuy && entry >= tick.ask - minGap) || (!isBuy && entry <= tick.bid + minGap)))
   {
      Alert("TuanProtrade: Giá Entry không ở vị trí Limit hợp lệ (Buy Limit phải < Ask, Sell Limit phải > Bid).");
      return;
   }
   if((g_entryMode == ENTRY_MODE_STOP || g_entryMode == ENTRY_MODE_STOP_LIMIT) &&
      ((isBuy && entry <= tick.ask + minGap) || (!isBuy && entry >= tick.bid - minGap)))
   {
      Alert("TuanProtrade: Giá kích hoạt Stop không hợp lệ (Buy Stop phải > Ask, Sell Stop phải < Bid).");
      return;
   }

   if(g_virtualTPOn && g_enPartial && MathAbs(g_targetRR - g_partialRR) < 0.05)
   {
      double riskDist = MathAbs(sizingEntryRef - sl), sign = isBuy ? 1.0 : -1.0;
      tp = NormalizePriceToTickSize(execSym, sizingEntryRef + sign * riskDist * (g_partialRR + 0.25));
   }

   double budget = GetRiskCashBudget(1.0, reason);
   if(budget <= 0.0)
   {
      Alert("TuanProtrade: ", reason);
      return;
   }

   // Chọn mức SL làm cơ sở định cỡ Lot theo cấu hình InpVirtualSlSizingBasis
   double sizingStop = (g_virtualSLOn && InpVirtualSlSizingBasis == VSL_SIZE_BY_EMERGENCY_STOP && serverSL > 0.0)
                       ? serverSL : sl;
   double volume = 0.0, riskAtMin = 0.0;
   if(!CalculateSafeVolume(isBuy, sizingEntryRef, sizingStop, budget, volume, riskAtMin))
   {
      Alert(StringFormat("TuanProtrade: Lot tối thiểu vượt ngân sách Risk (cần $%.2f, ngân sách $%.2f). Không gửi lệnh.", riskAtMin, budget));
      return;
   }

   if(g_enteredManualLot > 0.0)
      volume = FloorLotStep(MathMin(volume, g_enteredManualLot));

   if(InpSplitSetupRiskAcrossOrders)
   {
      int currentActiveLegs = CountPositionsInScope(false);
      if(currentActiveLegs == 0 && g_leg1SuggestedLot > 0.0 && g_enteredManualLot <= 0.0)
      {
         double fullVol = volume;   // [v12.1] báo rõ Nhịp 1 chỉ là một phần của lot đầy đủ
         volume = FloorLotStep(MathMin(volume, g_leg1SuggestedLot));
         if(fullVol > 0.0 && volume < fullVol)
            SetToastStatus(StringFormat("Chia lệnh: Nhịp 1 = %.2f lot (%.0f%% của %.2f lot đầy đủ). Bấm lệnh tiếp để vào các nhịp sau.",
                                        volume, volume / fullVol * 100.0, fullVol));
      }
      else if(currentActiveLegs > 0)
      {
         if(g_nextAddOnSuggestedLot <= 0.0)
         {
            Alert("TuanProtrade: Ngân sách Risk còn lại cho nhịp lệnh bổ sung bằng 0.");
            return;
         }
         volume = FloorLotStep(MathMin(volume, g_nextAddOnSuggestedLot));
      }
   }

   double minLot = SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN);
   if(volume < minLot)
   {
      Alert("TuanProtrade: Khối lượng sau khi áp dụng giới hạn Risk nhỏ hơn Lot tối thiểu của sàn.");
      return;
   }

   trade.SetExpertMagicNumber((ulong)InpTradeMagicNumber);
   trade.SetDeviationInPoints((ulong)MathMax(0, InpMaxDeviationPoints));
   trade.SetTypeFillingBySymbol(execSym);

   string note = isBuy ? "TradeDesk BUY" : "TradeDesk SELL";
   if(g_entryMode == ENTRY_MODE_LPO)        note += " LPO";
   if(g_entryMode == ENTRY_MODE_STOP_LIMIT) note += " STOPLIMIT";

   double brokerMax = SymbolInfoDouble(execSym, SYMBOL_VOLUME_MAX);
   double childMax  = (g_maxLotPerOrder > 0.0) ? MathMin(g_maxLotPerOrder, brokerMax) : brokerMax;
   childMax = FloorLotStep(childMax);
   if(childMax < minLot)
   {
      Alert("TuanProtrade: MaxLotPerOrder nhỏ hơn Lot tối thiểu của sàn.");
      return;
   }

   double requiredOrders = MathCeil(volume / childMax);
   int maxSplitOrders = MathMax(1, InpMaxSplitOrders);
   if(requiredOrders > maxSplitOrders)
   {
      Alert(StringFormat("TuanProtrade: Cần chia %.0f lệnh con, vượt giới hạn %d; chưa gửi lệnh.", requiredOrders, maxSplitOrders));
      return;
   }

   double remaining = volume;
   int sentCount = 0;
   bool allSent = true;
   while(remaining >= minLot - 1e-8)
   {
      double child    = FloorLotStep(MathMin(remaining, childMax));
      if(child < minLot) break;
      bool   sent     = false;
      double brokerTP = g_virtualTPOn ? 0.0 : tp;
      ulong  ordTicketOut = 0;

      if(g_entryMode == ENTRY_MODE_MARKET)
      {
         sent = isBuy ? trade.Buy(child, execSym, 0.0, serverSL, brokerTP, note)
                      : trade.Sell(child, execSym, 0.0, serverSL, brokerTP, note);
         sent = TradeRequestSucceeded(sent);
      }
      else if(g_entryMode == ENTRY_MODE_LIMIT || g_entryMode == ENTRY_MODE_LPO)
      {
         sent = isBuy ? trade.BuyLimit(child, entry, execSym, serverSL, brokerTP, ORDER_TIME_GTC, 0, note)
                      : trade.SellLimit(child, entry, execSym, serverSL, brokerTP, ORDER_TIME_GTC, 0, note);
         sent = TradeRequestSucceeded(sent);
         ordTicketOut = trade.ResultOrder();
      }
      else if(g_entryMode == ENTRY_MODE_STOP)
      {
         sent = isBuy ? trade.BuyStop(child, entry, execSym, serverSL, brokerTP, ORDER_TIME_GTC, 0, note)
                      : trade.SellStop(child, entry, execSym, serverSL, brokerTP, ORDER_TIME_GTC, 0, note);
         sent = TradeRequestSucceeded(sent);
         ordTicketOut = trade.ResultOrder();
      }
      else if(g_entryMode == ENTRY_MODE_STOP_LIMIT)
      {
         sent = SendNativeStopLimitOrder(isBuy, child, entry, stopLimitExecP, serverSL, brokerTP, note, ordTicketOut);
      }

      if(!sent)
      {
         allSent = false;
         break;
      }

      if(g_virtualSLOn)
      {
         if(g_entryMode == ENTRY_MODE_MARKET)
         {
            if(!SaveVirtualStopForDeal(trade.ResultDeal(), sl, serverSL))
               SaveVirtualStopForLatestPosition(isBuy, sl, serverSL);
         }
         else if(ordTicketOut > 0)
         {
            GlobalVariableSet(VirtualSLOrderKey(ordTicketOut), sl);
            GlobalVariableSet(VirtualEmergencySLOrderKey(ordTicketOut), serverSL);
         }
      }
      if(g_virtualTPOn)
      {
         if(g_entryMode == ENTRY_MODE_MARKET)
         {
            SaveVirtualTPForDeal(trade.ResultDeal(), tp);
            SaveVirtualTPForLatestPosition(isBuy, tp);
         }
         else if(ordTicketOut > 0)
         {
            GlobalVariableSet(VirtualTPOrderKey(ordTicketOut), tp);
         }
      }

      sentCount++;
      remaining = FloorLotStep(MathMax(0.0, remaining - child));
      if(remaining >= minLot && InpSplitOrderDelayMs > 0)
         Sleep(MathMin(2000, InpSplitOrderDelayMs));
   }

   if(sentCount == 0)
   {
      Alert(StringFormat("TuanProtrade: Lệnh không được máy chủ xác nhận. Retcode=%u — %s",
                         trade.ResultRetcode(), trade.ResultRetcodeDescription()));
   }
   else if(!allSent || remaining >= minLot)
   {
      Alert(StringFormat("TuanProtrade: Đã khớp một phần %.2f lot qua %d lệnh con; còn lại %.2f lot chưa gửi.",
                         volume - remaining, sentCount, remaining));
   }
   else
   {
      string okMsg = StringFormat("Đã gửi %s %.2f lot (%d lệnh con) | Risk $%.2f", note, volume, sentCount, budget);
      SetToastStatus(okMsg);
      Alert("TuanProtrade: " + okMsg);
   }

   if(sentCount > 0 && g_entryMode != ENTRY_MODE_MARKET)
   {
      string modeLbl = (g_entryMode == ENTRY_MODE_STOP) ? "STOP"
                       : ((g_entryMode == ENTRY_MODE_LPO) ? "LPO"
                       : ((g_entryMode == ENTRY_MODE_STOP_LIMIT) ? "STOP-LIMIT" : "LIMIT"));
      QueueTradeDeskNotification(StringFormat("TradeDesk PENDING PLACED | %s %s | %s | %.2f lot | entry %s",
                                              execSym, isBuy ? "BUY" : "SELL", modeLbl, volume,
                                              DoubleToString(sizingEntryRef, _Digits)), InpTelegramOnPending);
   }
}

//+------------------------------------------------------------------+
//| Đặt cặp lệnh OCO 4 chế độ với 100% Ngân sách Risk cho mỗi nhánh  |
//+------------------------------------------------------------------+
void PlaceOcoBracket()
{
   string abortKey = AccountScopedGV("TP_OCO_ABORT_" + GetExecutionSymbol());
   if(GlobalVariableCheck(abortKey) && GlobalVariableGet(abortKey) > 0.5)
   {
      ProcessFailedOcoCleanup();
      if(GlobalVariableCheck(abortKey))
      {
         Alert("TuanProtrade OCO: Đang chờ broker hủy OCO thất bại trước đó.");
         return;
      }
   }
   string reason = "";
   if(!TradeDeskEntryGate(reason))
   {
      Alert("TuanProtrade OCO: ", reason);
      return;
   }
   string execSym = GetExecutionSymbol();

   // Chế độ 5 (OCO_CUSTOM_ADOPT): Gom tất cả lệnh chờ hiện có trên Symbol vào 1 nhóm OCO
   if(g_ocoMode == OCO_CUSTOM_ADOPT)
   {
      // Adopt must not bypass portfolio risk or accept unknown stop-risk orders.
      if(InpMaxPortfolioRiskPct > 0.0)
      {
         double existingRisk = 0.0;
         if(!CalculateAccountExposureRisk(existingRisk) ||
            existingRisk > GetEffectiveEquity() * InpMaxPortfolioRiskPct / 100.0 + 0.01)
         {
            Alert("TuanProtrade OCO Adopt: rủi ro không xác định hoặc vượt trần danh mục; từ chối.");
            return;
         }
      }
      int adopted = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong tk = OrderGetTicket(i);
         if(tk > 0 && (OrderGetString(ORDER_SYMBOL) == _Symbol || OrderGetString(ORDER_SYMBOL) == execSym))
            adopted++;
      }
      if(adopted < 2)
      {
         Alert("TuanProtrade OCO Adopt: Cần ít nhất 2 lệnh chờ đang mở trên Symbol để liên kết OCO.");
         return;
      }
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong tk = OrderGetTicket(i);
         if(tk > 0 && (OrderGetString(ORDER_SYMBOL) == _Symbol || OrderGetString(ORDER_SYMBOL) == execSym))
            GlobalVariableSet(AccountScopedGV("TD_OCOTK_" + IntegerToString((long)tk)), 1.0);
      }
      // At this point, at least two pending orders were found and marked.
      SetToastStatus(StringFormat("Đã liên kết %d lệnh chờ vào nhóm OCO!", adopted));
      Alert(StringFormat("TuanProtrade OCO: Đã liên kết %d lệnh chờ hiện có trên %s vào nhóm OCO tự hủy lẫn nhau.", adopted, _Symbol));
      return;
   }

   if(CountPositionsInScope(false) > 0)
   {
      Alert("TuanProtrade OCO: Hãy đóng vị thế đang mở trên Symbol trước khi tạo cặp OCO mới.");
      return;
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t > 0 && (OrderGetString(ORDER_SYMBOL) == _Symbol || OrderGetString(ORDER_SYMBOL) == execSym) &&
         (ulong)OrderGetInteger(ORDER_MAGIC) == (ulong)InpTradeMagicNumber &&
         StringFind(OrderGetString(ORDER_COMMENT), "TDOCO_") == 0)
      {
         Alert("TuanProtrade OCO: Đã có cặp OCO đang chờ trên Symbol này.");
         return;
      }
   }

   MqlTick tick;
   if(!SymbolInfoTick(execSym, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
   {
      Alert("TuanProtrade OCO: Giá Bid/Ask chưa hợp lệ.");
      return;
   }

   double execPoint = SymbolInfoDouble(execSym, SYMBOL_POINT);
   if(execPoint <= 0.0) return;
   double atr    = (g_pineLatestAtr > 0.0) ? g_pineLatestAtr : ((g_pineFirstBarSlDist > 0.0) ? g_pineFirstBarSlDist : 100.0 * execPoint);
   double minGap = (double)MathMax(1, (int)SymbolInfoInteger(execSym, SYMBOL_TRADE_STOPS_LEVEL) + 1) * execPoint;
   double gap    = MathMax(atr * MathMax(0.1, InpOcoDistanceAtr), minGap);
   double stopDistance = MathMax((g_pineFirstBarSlDist > 0.0) ? g_pineFirstBarSlDist : atr * MathMax(0.1, g_customValueForFirstDay), gap);

   // TUANPROTRADE SAFETY: BOTH OCO branches can fill before cancellation.
   // Each branch reserves at most half the setup risk budget (worst-case = 100%).
   double budget = GetRiskCashBudget(1.0, reason) * 0.5;
   if(budget <= 0.0)
   {
      Alert("TuanProtrade OCO: ", reason);
      return;
   }

   trade.SetExpertMagicNumber((ulong)InpTradeMagicNumber);
   trade.SetDeviationInPoints((ulong)MathMax(0, InpMaxDeviationPoints));
   trade.SetTypeFillingBySymbol(execSym);

   bool   leg1Sent = false, leg2Sent = false;
   ulong  leg1Tk   = 0,     leg2Tk   = 0;
   double lot1     = 0.0,   lot2     = 0.0;
   double rMin1    = 0.0,   rMin2    = 0.0;
   double p1       = 0.0,   p2       = 0.0;

   // --- Chế độ 1: Breakout (Buy Stop phía trên + Sell Stop phía dưới) ---
   if(g_ocoMode == OCO_BREAKOUT_STOP_STOP)
   {
      p1 = NormalizePriceToTickSize(execSym, tick.ask + gap);
      p2 = NormalizePriceToTickSize(execSym, tick.bid - gap);
      double bsl = NormalizePriceToTickSize(execSym, p1 - stopDistance);
      double btp = NormalizePriceToTickSize(execSym, p1 + stopDistance * MathMax(0.1, g_targetRR));
      double ssl = NormalizePriceToTickSize(execSym, p2 + stopDistance);
      double stp = NormalizePriceToTickSize(execSym, p2 - stopDistance * MathMax(0.1, g_targetRR));

      if(!CalculateSafeVolume(true, p1, bsl, budget, lot1, rMin1) ||
         !CalculateSafeVolume(false, p2, ssl, budget, lot2, rMin2))
      {
         Alert("TuanProtrade OCO: Lot tối thiểu của một nhánh vượt ngân sách Risk; không tạo cặp.");
         return;
      }
      if(g_maxLotPerOrder > 0.0)
      {
         lot1 = FloorLotStep(MathMin(lot1, g_maxLotPerOrder));
         lot2 = FloorLotStep(MathMin(lot2, g_maxLotPerOrder));
      }
      if(lot1 < SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN) || lot2 < SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN))
      {
         Alert("TuanProtrade OCO: Cap lot nhỏ hơn lot tối thiểu của sàn.");
         return;
      }
      leg1Sent = TradeRequestSucceeded(trade.BuyStop(lot1, p1, execSym, bsl, btp, ORDER_TIME_GTC, 0, "TDOCO_B"));
      leg1Tk   = leg1Sent ? trade.ResultOrder() : 0;
      if(leg1Sent)
      {
         leg2Sent = TradeRequestSucceeded(trade.SellStop(lot2, p2, execSym, ssl, stp, ORDER_TIME_GTC, 0, "TDOCO_S"));
         leg2Tk   = leg2Sent ? trade.ResultOrder() : 0;
      }
   }
   // --- Chế độ 2: Reversal Sideway (Buy Limit phía dưới + Sell Limit phía trên) ---
   else if(g_ocoMode == OCO_REVERSAL_LIMIT_LIMIT)
   {
      p1 = NormalizePriceToTickSize(execSym, tick.ask - gap);
      p2 = NormalizePriceToTickSize(execSym, tick.bid + gap);
      double bsl = NormalizePriceToTickSize(execSym, p1 - stopDistance);
      double btp = NormalizePriceToTickSize(execSym, p1 + stopDistance * MathMax(0.1, g_targetRR));
      double ssl = NormalizePriceToTickSize(execSym, p2 + stopDistance);
      double stp = NormalizePriceToTickSize(execSym, p2 - stopDistance * MathMax(0.1, g_targetRR));

      if(!CalculateSafeVolume(true, p1, bsl, budget, lot1, rMin1) ||
         !CalculateSafeVolume(false, p2, ssl, budget, lot2, rMin2))
      {
         Alert("TuanProtrade OCO Limit-Limit: Lot tối thiểu vượt ngân sách Risk.");
         return;
      }
      if(g_maxLotPerOrder > 0.0)
      {
         lot1 = FloorLotStep(MathMin(lot1, g_maxLotPerOrder));
         lot2 = FloorLotStep(MathMin(lot2, g_maxLotPerOrder));
      }
      if(lot1 < SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN) || lot2 < SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN))
      {
         Alert("TuanProtrade OCO: Cap lot nhỏ hơn lot tối thiểu của sàn.");
         return;
      }
      leg1Sent = TradeRequestSucceeded(trade.BuyLimit(lot1, p1, execSym, bsl, btp, ORDER_TIME_GTC, 0, "TDOCO_BL"));
      leg1Tk   = leg1Sent ? trade.ResultOrder() : 0;
      if(leg1Sent)
      {
         leg2Sent = TradeRequestSucceeded(trade.SellLimit(lot2, p2, execSym, ssl, stp, ORDER_TIME_GTC, 0, "TDOCO_SL"));
         leg2Tk   = leg2Sent ? trade.ResultOrder() : 0;
      }
   }
   // --- Chế độ 3: Directional Buy (Buy Limit đón hồi + Buy Stop đón phá cản) ---
   else if(g_ocoMode == OCO_DIRECTIONAL_BUY)
   {
      p1 = NormalizePriceToTickSize(execSym, tick.ask - gap);
      p2 = NormalizePriceToTickSize(execSym, tick.ask + gap);
      double bsl1 = NormalizePriceToTickSize(execSym, p1 - stopDistance);
      double btp1 = NormalizePriceToTickSize(execSym, p1 + stopDistance * MathMax(0.1, g_targetRR));
      double bsl2 = NormalizePriceToTickSize(execSym, p2 - stopDistance);
      double btp2 = NormalizePriceToTickSize(execSym, p2 + stopDistance * MathMax(0.1, g_targetRR));

      if(!CalculateSafeVolume(true, p1, bsl1, budget, lot1, rMin1) ||
         !CalculateSafeVolume(true, p2, bsl2, budget, lot2, rMin2))
      {
         Alert("TuanProtrade OCO Directional Buy: Lot tối thiểu vượt ngân sách Risk.");
         return;
      }
      if(g_maxLotPerOrder > 0.0)
      {
         lot1 = FloorLotStep(MathMin(lot1, g_maxLotPerOrder));
         lot2 = FloorLotStep(MathMin(lot2, g_maxLotPerOrder));
      }
      if(lot1 < SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN) || lot2 < SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN))
      {
         Alert("TuanProtrade OCO: Cap lot nhỏ hơn lot tối thiểu của sàn.");
         return;
      }
      leg1Sent = TradeRequestSucceeded(trade.BuyLimit(lot1, p1, execSym, bsl1, btp1, ORDER_TIME_GTC, 0, "TDOCO_DBL"));
      leg1Tk   = leg1Sent ? trade.ResultOrder() : 0;
      if(leg1Sent)
      {
         leg2Sent = TradeRequestSucceeded(trade.BuyStop(lot2, p2, execSym, bsl2, btp2, ORDER_TIME_GTC, 0, "TDOCO_DBS"));
         leg2Tk   = leg2Sent ? trade.ResultOrder() : 0;
      }
   }
   // --- Chế độ 4: Directional Sell (Sell Limit đón hồi + Sell Stop đón phá đáy) ---
   else if(g_ocoMode == OCO_DIRECTIONAL_SELL)
   {
      p1 = NormalizePriceToTickSize(execSym, tick.bid + gap);
      p2 = NormalizePriceToTickSize(execSym, tick.bid - gap);
      double ssl1 = NormalizePriceToTickSize(execSym, p1 + stopDistance);
      double stp1 = NormalizePriceToTickSize(execSym, p1 - stopDistance * MathMax(0.1, g_targetRR));
      double ssl2 = NormalizePriceToTickSize(execSym, p2 + stopDistance);
      double stp2 = NormalizePriceToTickSize(execSym, p2 - stopDistance * MathMax(0.1, g_targetRR));

      if(!CalculateSafeVolume(false, p1, ssl1, budget, lot1, rMin1) ||
         !CalculateSafeVolume(false, p2, ssl2, budget, lot2, rMin2))
      {
         Alert("TuanProtrade OCO Directional Sell: Lot tối thiểu vượt ngân sách Risk.");
         return;
      }
      if(g_maxLotPerOrder > 0.0)
      {
         lot1 = FloorLotStep(MathMin(lot1, g_maxLotPerOrder));
         lot2 = FloorLotStep(MathMin(lot2, g_maxLotPerOrder));
      }
      if(lot1 < SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN) || lot2 < SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN))
      {
         Alert("TuanProtrade OCO: Cap lot nhỏ hơn lot tối thiểu của sàn.");
         return;
      }
      leg1Sent = TradeRequestSucceeded(trade.SellLimit(lot1, p1, execSym, ssl1, stp1, ORDER_TIME_GTC, 0, "TDOCO_DSL"));
      leg1Tk   = leg1Sent ? trade.ResultOrder() : 0;
      if(leg1Sent)
      {
         leg2Sent = TradeRequestSucceeded(trade.SellStop(lot2, p2, execSym, ssl2, stp2, ORDER_TIME_GTC, 0, "TDOCO_DSS"));
         leg2Tk   = leg2Sent ? trade.ResultOrder() : 0;
      }
   }

   if(!leg1Sent || !leg2Sent)
   {
      // A rejected order deletion must not leave an unmanaged orphan pending order.
      GlobalVariableSet(AccountScopedGV("TP_OCO_ABORT_" + execSym), 1.0);
      ProcessFailedOcoCleanup();
      Alert(StringFormat("TuanProtrade OCO: Một nhánh bị từ chối (%u %s); đang tiếp tục hủy nhánh còn lại nếu broker chưa xác nhận.",
                         trade.ResultRetcode(), trade.ResultRetcodeDescription()));
      return;
   }

   GlobalVariableSet(AccountScopedGV("TD_OCOTK_" + IntegerToString((long)leg1Tk)), 1.0);
   GlobalVariableSet(AccountScopedGV("TD_OCOTK_" + IntegerToString((long)leg2Tk)), 1.0);

   string msg = StringFormat("Đã đặt cặp OCO (50%% Risk/nhánh, tổng tối đa 100%%): %.2fL @ %s & %.2fL @ %s",
                             lot1, DoubleToString(p1, _Digits), lot2, DoubleToString(p2, _Digits));
   SetToastStatus(msg);
   Alert("TuanProtrade: " + msg);
   QueueTradeDeskNotification("TuanProtrade OCO PLACED | " + _Symbol + " | " + msg, InpTelegramOnPending);
}

//+------------------------------------------------------------------+
//| Retry OCO rollback when broker refuses to cancel surviving leg.  |
//+------------------------------------------------------------------+
void ProcessFailedOcoCleanup()
{
   string execSym = GetExecutionSymbol();
   string rollbackKey = AccountScopedGV("TP_OCO_ABORT_" + execSym);
   if(!GlobalVariableCheck(rollbackKey) || GlobalVariableGet(rollbackKey) < 0.5)
      return;

   bool unfinished = false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong orderTicket = OrderGetTicket(i);
      if(orderTicket == 0) continue;
      string sym = OrderGetString(ORDER_SYMBOL);
      if(sym != execSym && sym != _Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != (ulong)InpTradeMagicNumber) continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), "TDOCO_") != 0) continue;
      DeleteOrderWithConfirmation(orderTicket);
      if(OrderSelect(orderTicket))
         unfinished = true;
   }
   if(!unfinished)
      GlobalVariableDel(rollbackKey);
}

//+------------------------------------------------------------------+
//| Hủy các lệnh chờ OCO còn lại ngay khi 1 lệnh trong nhóm khớp     |
//+------------------------------------------------------------------+
void CancelOcoPending(string groupFilter)
{
   string execSym = GetExecutionSymbol();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t == 0) continue;
      string s = OrderGetString(ORDER_SYMBOL);
      if(s != _Symbol && s != execSym) continue;

      string ocoTkKey = AccountScopedGV("TD_OCOTK_" + IntegerToString((long)t));
      bool isOcoComment = ((ulong)OrderGetInteger(ORDER_MAGIC) == (ulong)InpTradeMagicNumber &&
                           StringFind(OrderGetString(ORDER_COMMENT), "TDOCO_") == 0);
      bool isAdoptedOco = GlobalVariableCheck(ocoTkKey);

      if(isOcoComment || isAdoptedOco)
      {
         DeleteOrderWithConfirmation(t);
         GlobalVariableDel(ocoTkKey);
      }
   }

   // Đồng thời hủy các lệnh chờ ảo thuộc nhóm OCO trong Virtual Order Book
   for(int v = 0; v < 20; v++)
   {
      if(g_virtualOrders[v].state != VORD_INACTIVE && g_virtualOrders[v].ocoGroupId != "")
      {
         if(groupFilter == "" || g_virtualOrders[v].ocoGroupId == groupFilter)
            g_virtualOrders[v].state = VORD_INACTIVE;
      }
   }
}

void CancelTradeDeskPending()
{
   string execSym = GetExecutionSymbol();
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t > 0 && (OrderGetString(ORDER_SYMBOL) == _Symbol || OrderGetString(ORDER_SYMBOL) == execSym) &&
         (ulong)OrderGetInteger(ORDER_MAGIC) == (ulong)InpTradeMagicNumber)
      {
         n++;
         DeleteOrderWithConfirmation(t);
         GlobalVariableDel(VirtualTPOrderKey(t));
         GlobalVariableDel(VirtualSLOrderKey(t));
         GlobalVariableDel(VirtualEmergencySLOrderKey(t));
         GlobalVariableDel(AccountScopedGV("TD_OCOTK_" + IntegerToString((long)t)));
         GlobalVariableDel(AccountScopedGV("TD_PMOVES_" + IntegerToString((long)t)));
      }
   }
   if(n == 0)
      Alert("TuanProtrade: Không có lệnh chờ nào do EA này tạo trên Symbol hiện tại.");
   else
   {
      SetToastStatus(StringFormat("Đã hủy %d lệnh chờ của EA", n));
      Alert(StringFormat("TuanProtrade: Đã gửi yêu cầu hủy %d lệnh chờ trên %s.", n, _Symbol));
      QueueTradeDeskNotification(StringFormat("TradeDesk PENDING CANCELLED | %s | đã xóa %d lệnh chờ", _Symbol, n), InpTelegramOnPending);
   }
}

//+------------------------------------------------------------------+
//| Trailing Lệnh Chờ (Đã sửa chuẩn hướng dịch chuyển cho Limit/Stop)|
//+------------------------------------------------------------------+
void ProcessPendingOrderTrailing()
{
   if(!g_pendingTrailOn || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
      return;

   string execSym = GetExecutionSymbol();
   MqlTick tick;
   if(!SymbolInfoTick(execSym, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
      return;

   double point  = SymbolInfoDouble(execSym, SYMBOL_POINT);
   double minGap = (double)MathMax(1, (int)SymbolInfoInteger(execSym, SYMBOL_TRADE_STOPS_LEVEL) + 1) * point;
   double atr    = (g_pineLatestAtr > 0.0) ? g_pineLatestAtr : 100.0 * point;
   double gap    = (InpPendingTrailDistPts > 0) ? MathMax(InpPendingTrailDistPts * point, minGap)
                                                : MathMax(atr * MathMax(0.1, InpOcoDistanceAtr), minGap);
   double step   = MathMax(1, InpPendingTrailStepPts) * point;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      string s = OrderGetString(ORDER_SYMBOL);
      if((s != _Symbol && s != execSym) || (ulong)OrderGetInteger(ORDER_MAGIC) != (ulong)InpTradeMagicNumber)
         continue;

      string movesKey = AccountScopedGV("TD_PMOVES_" + IntegerToString((long)ticket));
      int movesDone = GlobalVariableCheck(movesKey) ? (int)GlobalVariableGet(movesKey) : 0;
      if(InpPendingTrailMaxMoves > 0 && movesDone >= InpPendingTrailMaxMoves)
         continue;

      long type = OrderGetInteger(ORDER_TYPE);
      if(type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT &&
         type != ORDER_TYPE_BUY_STOP  && type != ORDER_TYPE_SELL_STOP)
         continue;

      double oldPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      double sl       = OrderGetDouble(ORDER_SL);
      double tp       = OrderGetDouble(ORDER_TP);
      double wanted   = oldPrice;
      bool   move     = false;

      // Quy tắc chuẩn:
      // - BUY_LIMIT (nằm dưới Ask): chỉ kéo LÊN khi giá Ask tăng bỏ xa lệnh chờ (Ask - oldPrice > gap + step)
      // - SELL_LIMIT (nằm trên Bid): chỉ kéo XUỐNG khi giá Bid giảm bỏ xa lệnh chờ (oldPrice - Bid > gap + step)
      // - BUY_STOP (nằm trên Ask): chỉ kéo XUỐNG khi giá Ask giảm xa khỏi lệnh chờ (oldPrice - Ask > gap + step)
      // - SELL_STOP (nằm dưới Bid): chỉ kéo LÊN khi giá Bid tăng xa khỏi lệnh chờ (Bid - oldPrice > gap + step)
      if(type == ORDER_TYPE_BUY_LIMIT)
      {
         wanted = NormalizePriceToTickSize(execSym, tick.ask - gap);
         move   = (wanted >= oldPrice + step - point * 0.1 && wanted < tick.ask - minGap);
      }
      else if(type == ORDER_TYPE_SELL_LIMIT)
      {
         wanted = NormalizePriceToTickSize(execSym, tick.bid + gap);
         move   = (wanted <= oldPrice - step + point * 0.1 && wanted > tick.bid + minGap);
      }
      else if(type == ORDER_TYPE_BUY_STOP)
      {
         wanted = NormalizePriceToTickSize(execSym, tick.ask + gap);
         move   = (wanted <= oldPrice - step + point * 0.1 && wanted > tick.ask + minGap);
      }
      else if(type == ORDER_TYPE_SELL_STOP)
      {
         wanted = NormalizePriceToTickSize(execSym, tick.bid - gap);
         move   = (wanted >= oldPrice + step - point * 0.1 && wanted < tick.bid - minGap);
      }

      if(!move || wanted <= 0.0)
         continue;

      double shift = wanted - oldPrice;
      double newSL = (sl > 0.0) ? NormalizePriceToTickSize(execSym, sl + shift) : 0.0;
      double newTP = (tp > 0.0) ? NormalizePriceToTickSize(execSym, tp + shift) : 0.0;

      ENUM_ORDER_TYPE_TIME timeType = (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME);
      datetime expiration = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      trade.SetExpertMagicNumber((ulong)InpTradeMagicNumber);
      if(TradeRequestSucceeded(trade.OrderModify(ticket, wanted, newSL, newTP, timeType, expiration, 0.0)))
      {
         GlobalVariableSet(movesKey, (double)(movesDone + 1));
         string vTpOrdKey = VirtualTPOrderKey(ticket);
         if(GlobalVariableCheck(vTpOrdKey))
            GlobalVariableSet(vTpOrdKey, NormalizePriceToTickSize(execSym, GlobalVariableGet(vTpOrdKey) + shift));
         string vSlOrdKey = VirtualSLOrderKey(ticket);
         if(GlobalVariableCheck(vSlOrdKey))
            GlobalVariableSet(vSlOrdKey, NormalizePriceToTickSize(execSym, GlobalVariableGet(vSlOrdKey) + shift));
         string vEmgOrdKey = VirtualEmergencySLOrderKey(ticket);
         if(GlobalVariableCheck(vEmgOrdKey))
            GlobalVariableSet(vEmgOrdKey, NormalizePriceToTickSize(execSym, GlobalVariableGet(vEmgOrdKey) + shift));
      }
   }
}

// ============================================================================
// MODULE 7: CVirtualStealthEngine (SỔ 20 LỆNH ẢO, LPO 2 PHA & VIRTUAL SL/TP)
// ============================================================================

string VirtualPendingKey(string suffix)
{
   return AccountScopedGV("TD_VP_" + IntegerToString((long)ChartID()) + "_" + suffix);
}

string GetVirtualBookFileName()
{
   return StringFormat("TradeDeskPro_VBook_%I64d_%d_%s.dat",
                       AccountInfoInteger(ACCOUNT_LOGIN), GetCurrentServerHash(), _Symbol);
}

//+------------------------------------------------------------------+
//| Lưu và nạp Sổ 20 Lệnh Chờ Ảo từ tệp bền vững                     |
//+------------------------------------------------------------------+
void SaveVirtualOrderBookToFile()
{
   string fn = GetVirtualBookFileName();
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;

   int activeCnt = 0;
   for(int i = 0; i < 20; i++)
   {
      if(g_virtualOrders[i].state == VORD_INACTIVE)
         continue;
      activeCnt++;
      FileWriteString(h, StringFormat("%d;%d;%d;%d;%.6f;%.6f;%.6f;%.6f;%.2f;%d;%I64d;%I64d;%s\r\n",
                      g_virtualOrders[i].slotId,
                      (int)g_virtualOrders[i].state,
                      g_virtualOrders[i].isBuy ? 1 : 0,
                      (int)g_virtualOrders[i].mode,
                      g_virtualOrders[i].entryPrice,
                      g_virtualOrders[i].stopLimitPrice,
                      g_virtualOrders[i].slPrice,
                      g_virtualOrders[i].tpPrice,
                      g_virtualOrders[i].lotSize,
                      g_virtualOrders[i].pullbackPts,
                      (long)g_virtualOrders[i].createdTime,
                      (long)g_virtualOrders[i].expiryTime,
                      g_virtualOrders[i].ocoGroupId));
   }
   FileClose(h);
   g_virtualPendingActive = (activeCnt > 0);
}

void DrawVirtualPendingLine()
{
   int activeCount = 0;
   for(int i = 0; i < 20; i++)
   {
      string obj = VIS_PREFIX + "VPENDING_" + IntegerToString(i);
      if(g_virtualOrders[i].state == VORD_INACTIVE || g_virtualOrders[i].entryPrice <= 0.0)
      {
         ObjectDelete(0, obj);
         continue;
      }
      activeCount++;
      double drawPx = (g_virtualOrders[i].state == VORD_LPO_PHASE2_TRAIL_REV ||
                       g_virtualOrders[i].state == VORD_STOPLIMIT_PHASE2_LIMIT)
                      ? g_virtualOrders[i].stopLimitPrice
                      : g_virtualOrders[i].entryPrice;

      if(ObjectFind(0, obj) < 0)
      {
         ObjectCreate(0, obj, OBJ_HLINE, 0, 0, drawPx);
         ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, obj, OBJPROP_SELECTED, true);
         ObjectSetInteger(0, obj, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, obj, OBJPROP_WIDTH, 2);
      }
      ObjectSetDouble(0, obj, OBJPROP_PRICE, 0, drawPx);
      color c = (g_virtualOrders[i].state == VORD_LPO_PHASE2_TRAIL_REV) ? clrGold
                : (g_virtualOrders[i].isBuy ? C_BTN_BUY : C_BTN_SELL);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, c);

      string typeLbl = "V-LIMIT";
      if(g_virtualOrders[i].mode == ENTRY_MODE_STOP)       typeLbl = "V-STOP";
      else if(g_virtualOrders[i].mode == ENTRY_MODE_LPO)
         typeLbl = (g_virtualOrders[i].state == VORD_LPO_PHASE2_TRAIL_REV) ? "V-LPO [PHA 2: BÁM ĐẢO CHIỀU]" : "V-LPO [PHA 1: CHỜ CHẠM VÙNG]";
      else if(g_virtualOrders[i].mode == ENTRY_MODE_STOP_LIMIT)
         typeLbl = (g_virtualOrders[i].state == VORD_STOPLIMIT_PHASE2_LIMIT) ? "V-STOPLIMIT [PHA 2: CHỜ LIMIT]" : "V-STOPLIMIT [PHA 1: CHỜ STOP]";

      ObjectSetString(0, obj, OBJPROP_TEXT, StringFormat("#%d %s %s @ %s",
                      i + 1, typeLbl, g_virtualOrders[i].isBuy ? "BUY" : "SELL", DoubleToString(drawPx, _Digits)));
   }
   ObjectDelete(0, VIS_PREFIX + "VPENDING");
   g_virtualPendingActive = (activeCount > 0);
}

void ClearVirtualPending(string reason = "")
{
   for(int i = 0; i < 20; i++)
   {
      g_virtualOrders[i].state = VORD_INACTIVE;
      ObjectDelete(0, VIS_PREFIX + "VPENDING_" + IntegerToString(i));
   }
   g_virtualPendingActive = false;
   GlobalVariableSet(VirtualPendingKey("ACTIVE"), 0.0);
   GlobalVariableDel(VirtualPendingKey("ENTRY"));
   GlobalVariableDel(VirtualPendingKey("SL"));
   GlobalVariableDel(VirtualPendingKey("TP"));
   GlobalVariableDel(VirtualPendingKey("BUY"));
   GlobalVariableDel(VirtualPendingKey("MODE"));
   GlobalVariableDel(VirtualPendingKey("TIME"));
   ObjectDelete(0, VIS_PREFIX + "VPENDING");
   SaveVirtualOrderBookToFile();
   if(reason != "")
   {
      SetToastStatus("Lệnh ảo: " + reason);
      Alert("TradeDesk Lệnh chờ ảo: " + reason);
   }
}

void LoadVirtualPending()
{
   for(int i = 0; i < 20; i++)
   {
      g_virtualOrders[i].slotId = i;
      g_virtualOrders[i].state  = VORD_INACTIVE;
   }

   string fn = GetVirtualBookFileName();
   int loadedCount = 0;
   if(FileIsExist(fn))
   {
      int h = FileOpen(fn, FILE_READ | FILE_TXT | FILE_ANSI);
      if(h != INVALID_HANDLE)
      {
         while(!FileIsEnding(h))
         {
            string line = FileReadString(h);
            string cols[];
            if(StringSplit(line, ';', cols) >= 12)
            {
               int slot = (int)StringToInteger(cols[0]);
               if(slot >= 0 && slot < 20)
               {
                  g_virtualOrders[slot].slotId         = slot;
                  g_virtualOrders[slot].state          = (ENUM_VIRTUAL_ORD_STATE)StringToInteger(cols[1]);
                  g_virtualOrders[slot].symbol         = _Symbol;
                  g_virtualOrders[slot].isBuy          = (StringToInteger(cols[2]) != 0);
                  g_virtualOrders[slot].mode           = (ENUM_ORDER_ENTRY_MODE)StringToInteger(cols[3]);
                  g_virtualOrders[slot].entryPrice     = StringToDouble(cols[4]);
                  g_virtualOrders[slot].stopLimitPrice = StringToDouble(cols[5]);
                  g_virtualOrders[slot].slPrice        = StringToDouble(cols[6]);
                  g_virtualOrders[slot].tpPrice        = StringToDouble(cols[7]);
                  g_virtualOrders[slot].lotSize        = StringToDouble(cols[8]);
                  g_virtualOrders[slot].pullbackPts    = (int)StringToInteger(cols[9]);
                  g_virtualOrders[slot].createdTime    = (datetime)StringToInteger(cols[10]);
                  g_virtualOrders[slot].expiryTime     = (datetime)StringToInteger(cols[11]);
                  g_virtualOrders[slot].ocoGroupId     = (ArraySize(cols) >= 13) ? cols[12] : "";
                  if(g_virtualOrders[slot].state != VORD_INACTIVE)
                     loadedCount++;
               }
            }
         }
         FileClose(h);
      }
   }

   // Tương thích ngược với biến đơn GV của v9.10 nếu tệp chưa có dữ liệu
   string activeKey = VirtualPendingKey("ACTIVE");
   if(loadedCount == 0 && GlobalVariableCheck(activeKey) && GlobalVariableGet(activeKey) > 0.5)
   {
      if(GlobalVariableCheck(VirtualPendingKey("ENTRY")) && GlobalVariableCheck(VirtualPendingKey("SL")))
      {
         g_virtualOrders[0].slotId         = 0;
         g_virtualOrders[0].state          = VORD_ACTIVE_WAIT_TOUCH;
         g_virtualOrders[0].symbol         = _Symbol;
         g_virtualOrders[0].entryPrice     = GlobalVariableGet(VirtualPendingKey("ENTRY"));
         g_virtualOrders[0].stopLimitPrice = g_virtualOrders[0].entryPrice;
         g_virtualOrders[0].slPrice        = GlobalVariableGet(VirtualPendingKey("SL"));
         g_virtualOrders[0].tpPrice        = GlobalVariableCheck(VirtualPendingKey("TP")) ? GlobalVariableGet(VirtualPendingKey("TP")) : 0.0;
         g_virtualOrders[0].isBuy          = (GlobalVariableGet(VirtualPendingKey("BUY")) > 0.5);
         g_virtualOrders[0].mode           = (ENUM_ORDER_ENTRY_MODE)(int)GlobalVariableGet(VirtualPendingKey("MODE"));
         g_virtualOrders[0].pullbackPts    = g_pullbackPoints;
         g_virtualOrders[0].createdTime    = GlobalVariableCheck(VirtualPendingKey("TIME")) ? (datetime)GlobalVariableGet(VirtualPendingKey("TIME")) : TimeCurrent();
         g_virtualOrders[0].expiryTime     = (InpVirtualPendingExpiryHours > 0.0) ? (g_virtualOrders[0].createdTime + (datetime)(InpVirtualPendingExpiryHours * 3600)) : 0;
         loadedCount = 1;
      }
   }

   g_virtualPendingActive = (loadedCount > 0);
   if(loadedCount > 0)
   {
      g_virtualPendingEntry   = g_virtualOrders[0].entryPrice;
      g_virtualPendingSL      = g_virtualOrders[0].slPrice;
      g_virtualPendingTP      = g_virtualOrders[0].tpPrice;
      g_virtualPendingBuy     = g_virtualOrders[0].isBuy;
      g_virtualPendingMode    = (int)g_virtualOrders[0].mode;
      g_virtualPendingCreated = g_virtualOrders[0].createdTime;
   }
   DrawVirtualPendingLine();
}

//+------------------------------------------------------------------+
//| Đăng ký Lệnh Chờ Ảo mới (Limit, Stop, Stop-Limit, LPO 2 Pha)     |
//+------------------------------------------------------------------+
void ArmOrCancelVirtualPending()
{
   string reason = "";
   if(!TradeDeskEntryGate(reason))
   {
      Alert("TuanProtrade: ", reason);
      return;
   }
   if(g_entryMode == ENTRY_MODE_MARKET)
   {
      // Nếu đang ở Market mà bấm nút HỦY LỆNH ẢO khi có lệnh ảo đang chạy thì xóa hết lệnh ảo
      if(g_virtualPendingActive)
      {
         ClearVirtualPending("đã hủy toàn bộ theo thao tác người dùng");
         return;
      }
      Alert("TuanProtrade: Hãy chọn kiểu lệnh Limit, Stop, LPO hoặc Stop-Limit trước khi Arm lệnh ảo.");
      return;
   }

   // Tìm khe trống trong Sổ 20 Lệnh Chờ Ảo
   int freeSlot = -1;
   for(int s = 0; s < 20; s++)
   {
      if(g_virtualOrders[s].state == VORD_INACTIVE)
      {
         freeSlot = s;
         break;
      }
   }
   if(freeSlot < 0)
   {
      // Nếu đầy 20 khe hoặc người dùng bấm lại để hủy
      ClearVirtualPending("đã làm mới sổ lệnh chờ ảo");
      return;
   }

   string execSym = GetExecutionSymbol();
   MqlTick tick;
   if(!SymbolInfoTick(execSym, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
   {
      Alert("TuanProtrade: Không có giá Bid/Ask để Arm lệnh ảo.");
      return;
   }

   bool   isBuy = (g_tradeSide == SIDE_LONG);
   double entry = g_sizerEntryPrice;
   if(g_entryMode == ENTRY_MODE_LPO && (entry <= 0.0 || (isBuy && entry >= tick.ask) || (!isBuy && entry <= tick.bid)))
   {
      double gap = MathMax(g_pullbackPoints * _Point, (double)MathMax(1, (int)SymbolInfoInteger(execSym, SYMBOL_TRADE_STOPS_LEVEL) + 1) * _Point);
      entry = isBuy ? (tick.ask - gap) : (tick.bid + gap);
   }
   entry = NormalizePriceToTickSize(execSym, entry);
   if(entry <= 0.0)
   {
      Alert("TuanProtrade: Giá Entry lệnh ảo không hợp lệ.");
      return;
   }

   if((g_entryMode == ENTRY_MODE_LIMIT || g_entryMode == ENTRY_MODE_LPO) &&
      ((isBuy && entry >= tick.ask) || (!isBuy && entry <= tick.bid)))
   {
      Alert("TuanProtrade: Giá vùng Limit / LPO ảo phải nằm dưới Ask (với Buy) hoặc trên Bid (với Sell).");
      return;
   }
   if((g_entryMode == ENTRY_MODE_STOP || g_entryMode == ENTRY_MODE_STOP_LIMIT) &&
      ((isBuy && entry <= tick.ask) || (!isBuy && entry >= tick.bid)))
   {
      Alert("TuanProtrade: Giá kích hoạt Stop ảo phải nằm trên Ask (với Buy) hoặc dưới Bid (với Sell).");
      return;
   }

   double stopLimExec = (g_entryMode == ENTRY_MODE_STOP_LIMIT && g_sizerStopLimitPrice > 0.0)
                        ? NormalizePriceToTickSize(execSym, g_sizerStopLimitPrice) : entry;
   double sl = 0.0, tp = 0.0;
   if(!GetEntryProtection(isBuy, stopLimExec, sl, tp))
   {
      Alert("TuanProtrade: Không tính được SL/TP hợp lệ cho lệnh ảo.");
      return;
   }

   double armSizingSL = sl;
   if(g_virtualSLOn && InpVirtualSlSizingBasis == VSL_SIZE_BY_EMERGENCY_STOP && InpEnableEmergencyServerSL)
      armSizingSL = NormalizePriceToTickSize(execSym, stopLimExec + (isBuy ? -1.0 : 1.0) * MathAbs(stopLimExec - sl) * MathMax(1.05, InpEmergencySLMultiplier));

   double budget = GetRiskCashBudget(1.0, reason), vol = 0.0, riskAtMin = 0.0;
   if(budget <= 0.0 || !CalculateSafeVolume(isBuy, stopLimExec, armSizingSL, budget, vol, riskAtMin))
   {
      Alert("TuanProtrade: Lệnh ảo không đạt kiểm tra ngân sách Risk; ", reason);
      return;
   }

   g_virtualOrders[freeSlot].slotId         = freeSlot;
   g_virtualOrders[freeSlot].state          = VORD_ACTIVE_WAIT_TOUCH;
   g_virtualOrders[freeSlot].symbol         = _Symbol;
   g_virtualOrders[freeSlot].isBuy          = isBuy;
   g_virtualOrders[freeSlot].mode           = (ENUM_ORDER_ENTRY_MODE)g_entryMode;
   g_virtualOrders[freeSlot].entryPrice     = entry;
   g_virtualOrders[freeSlot].stopLimitPrice = stopLimExec;
   g_virtualOrders[freeSlot].slPrice        = sl;
   g_virtualOrders[freeSlot].tpPrice        = tp;
   g_virtualOrders[freeSlot].lotSize        = vol;
   g_virtualOrders[freeSlot].pullbackPts    = g_pullbackPoints;
   g_virtualOrders[freeSlot].createdTime    = TimeCurrent();
   g_virtualOrders[freeSlot].expiryTime     = (InpVirtualPendingExpiryHours > 0.0)
                                              ? (TimeCurrent() + (datetime)(InpVirtualPendingExpiryHours * 3600.0)) : 0;
   g_virtualOrders[freeSlot].ocoGroupId     = "";

   g_virtualPendingBuy     = isBuy;
   g_virtualPendingMode    = g_entryMode;
   g_virtualPendingEntry   = entry;
   g_virtualPendingSL      = sl;
   g_virtualPendingTP      = tp;
   g_virtualPendingCreated = g_virtualOrders[freeSlot].createdTime;
   g_virtualPendingActive  = true;

   GlobalVariableSet(VirtualPendingKey("ACTIVE"), 1.0);
   GlobalVariableSet(VirtualPendingKey("ENTRY"),  entry);
   GlobalVariableSet(VirtualPendingKey("SL"),     sl);
   GlobalVariableSet(VirtualPendingKey("TP"),     tp);
   GlobalVariableSet(VirtualPendingKey("BUY"),    isBuy ? 1.0 : 0.0);
   GlobalVariableSet(VirtualPendingKey("MODE"),   (double)g_entryMode);
   GlobalVariableSet(VirtualPendingKey("TIME"),   (double)g_virtualPendingCreated);

   SaveVirtualOrderBookToFile();
   DrawVirtualPendingLine();

   string typeName = (g_entryMode == ENTRY_MODE_LPO) ? "V-LPO 2 PHA"
                     : ((g_entryMode == ENTRY_MODE_STOP_LIMIT) ? "V-STOPLIMIT"
                     : ((g_entryMode == ENTRY_MODE_STOP) ? "V-STOP" : "V-LIMIT"));
   string msg = StringFormat("Đã Arm #%d %s %s tại %s (Lot dự kiến %.2f)",
                             freeSlot + 1, typeName, isBuy ? "BUY" : "SELL", DoubleToString(entry, _Digits), vol);
   SetToastStatus(msg);
   Alert("TuanProtrade: " + msg);
}

//+------------------------------------------------------------------+
//| Thực thi Sổ Lệnh Chờ Ảo & Máy Trạng Thái 2 Pha LPO / Stop-Limit  |
//+------------------------------------------------------------------+
void ProcessVirtualPending()
{
   if(!g_virtualPendingActive)
      return;

   string execSym = GetExecutionSymbol();
   MqlTick tick;
   if(!SymbolInfoTick(execSym, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
      return;

   bool bookChanged = false;
   datetime now = TimeCurrent();

   for(int i = 0; i < 20; i++)
   {
      if(g_virtualOrders[i].state == VORD_INACTIVE)
         continue;

      // 1. Kiểm tra hết hạn (Expiry)
      if(g_virtualOrders[i].expiryTime > 0 && now > g_virtualOrders[i].expiryTime)
      {
         g_virtualOrders[i].state = VORD_INACTIVE;
         bookChanged = true;
         Alert(StringFormat("TradeDesk Lệnh ảo #%d đã hết hạn và tự động hủy.", i + 1));
         continue;
      }

      bool   isBuy = g_virtualOrders[i].isBuy;
      double ask   = tick.ask;
      double bid   = tick.bid;
      bool   fireMarketNow = false;
      double execRefPrice  = g_virtualOrders[i].entryPrice;

      // 2. Xử lý Lệnh Limit / Stop Ảo chuẩn 1 pha
      if(g_virtualOrders[i].mode == ENTRY_MODE_LIMIT)
      {
         fireMarketNow = isBuy ? (ask <= g_virtualOrders[i].entryPrice) : (bid >= g_virtualOrders[i].entryPrice);
         execRefPrice  = isBuy ? ask : bid;
      }
      else if(g_virtualOrders[i].mode == ENTRY_MODE_STOP)
      {
         fireMarketNow = isBuy ? (ask >= g_virtualOrders[i].entryPrice) : (bid <= g_virtualOrders[i].entryPrice);
         execRefPrice  = isBuy ? ask : bid;
      }
      // 3. Xử lý Máy Trạng Thái 2 Pha cho Limit Pullback Order (LPO chuẩn InvestSoft)
      else if(g_virtualOrders[i].mode == ENTRY_MODE_LPO)
      {
         double pbDist = MathMax(1, g_virtualOrders[i].pullbackPts) * _Point;

         // Nếu giá xuyên thủng mức SL cấu trúc trong khi đang hồi -> hủy ngay LPO để bảo vệ tài khoản
         bool structuralSlBroken = isBuy ? (bid <= g_virtualOrders[i].slPrice) : (ask >= g_virtualOrders[i].slPrice);
         if(structuralSlBroken)
         {
            g_virtualOrders[i].state = VORD_INACTIVE;
            bookChanged = true;
            Alert(StringFormat("TradeDesk V-LPO #%d: Giá đã xuyên thủng mức SL cấu trúc (%s); tự động hủy lệnh LPO.",
                               i + 1, DoubleToString(g_virtualOrders[i].slPrice, _Digits)));
            continue;
         }

         if(g_virtualOrders[i].state == VORD_ACTIVE_WAIT_TOUCH)
         {
            // Pha 1: Chờ giá chạm vùng Limit
            bool touchedZone = isBuy ? (ask <= g_virtualOrders[i].entryPrice) : (bid >= g_virtualOrders[i].entryPrice);
            if(touchedZone)
            {
               g_virtualOrders[i].state          = VORD_LPO_PHASE2_TRAIL_REV;
               g_virtualOrders[i].stopLimitPrice = NormalizePriceToTickSize(execSym, isBuy ? (ask + pbDist) : (bid - pbDist));
               bookChanged = true;
               SetToastStatus(StringFormat("V-LPO #%d đã chạm vùng Limit -> Chuyển sang Pha 2 bám sóng hồi!", i + 1));
            }
         }
         else if(g_virtualOrders[i].state == VORD_LPO_PHASE2_TRAIL_REV)
         {
            // Pha 2: Kéo mức Stop bám sát cực trị sóng hồi; khớp ngay khi giá quay đầu đảo chiều một đoạn pbDist
            if(isBuy)
            {
               double candidateTrig = NormalizePriceToTickSize(execSym, ask + pbDist);
               if(candidateTrig < g_virtualOrders[i].stopLimitPrice - _Point * 0.1)
               {
                  g_virtualOrders[i].stopLimitPrice = candidateTrig;
                  bookChanged = true;
               }
               if(ask >= g_virtualOrders[i].stopLimitPrice)
               {
                  fireMarketNow = true;
                  execRefPrice  = ask;
               }
            }
            else
            {
               double candidateTrig = NormalizePriceToTickSize(execSym, bid - pbDist);
               if(candidateTrig > g_virtualOrders[i].stopLimitPrice + _Point * 0.1)
               {
                  g_virtualOrders[i].stopLimitPrice = candidateTrig;
                  bookChanged = true;
               }
               if(bid <= g_virtualOrders[i].stopLimitPrice)
               {
                  fireMarketNow = true;
                  execRefPrice  = bid;
               }
            }
         }
      }
      // 4. Xử lý Máy Trạng Thái 2 Pha cho Stop-Limit Ảo
      else if(g_virtualOrders[i].mode == ENTRY_MODE_STOP_LIMIT)
      {
         if(g_virtualOrders[i].state == VORD_ACTIVE_WAIT_TOUCH)
         {
            bool stopTouched = isBuy ? (ask >= g_virtualOrders[i].entryPrice) : (bid <= g_virtualOrders[i].entryPrice);
            if(stopTouched)
            {
               g_virtualOrders[i].state = VORD_STOPLIMIT_PHASE2_LIMIT;
               bookChanged = true;
            }
         }
         if(g_virtualOrders[i].state == VORD_STOPLIMIT_PHASE2_LIMIT)
         {
            fireMarketNow = isBuy ? (ask <= g_virtualOrders[i].stopLimitPrice) : (bid >= g_virtualOrders[i].stopLimitPrice);
            execRefPrice  = isBuy ? ask : bid;
         }
      }

      if(!fireMarketNow)
         continue;

      // Khi lệnh ảo kích hoạt: kiểm tra cổng an toàn TradeDeskEntryGate
      string gateReason = "";
      double plannedSL  = g_virtualOrders[i].slPrice;
      string ocoGrp     = g_virtualOrders[i].ocoGroupId;
      g_virtualOrders[i].state = VORD_INACTIVE;
      bookChanged = true;

      if(!TradeDeskEntryGate(gateReason))
      {
         Alert(StringFormat("TradeDesk Lệnh ảo #%d chạm giá nhưng bị chặn bởi cổng an toàn: %s", i + 1, gateReason));
         continue;
      }

      if(ocoGrp != "")
         CancelOcoPending(ocoGrp);

      // Thực thi gửi lệnh Market với tính toán lại Lot theo khoảng cách thực tế tới plannedSL
      int prevEntryMode = g_entryMode;
      ENUM_SL_CALC_MODE prevSlMode = g_slMode;
      bool   prevPinEntry    = g_pinSizerEntry;     // [v12.1] lưu trạng thái ghim trước khi kích hoạt lệnh ảo
      double prevPinnedEntry = g_sizerEntryPrice;
      double prevPinnedDist  = g_pinnedSlDist;
      g_tradeSide        = isBuy ? SIDE_LONG : SIDE_SHORT;
      g_entryMode        = ENTRY_MODE_MARKET;
      g_slMode           = SL_MODE_DRAG;
      g_pinSizerEntry    = true;
      g_sizerEntryPrice  = execRefPrice;
      g_sizerSlPrice     = plannedSL;
      g_pinnedSlDist     = MathAbs(execRefPrice - plannedSL);
      PlaceManualOrder(isBuy);
      g_entryMode        = prevEntryMode;
      g_slMode           = prevSlMode;
      g_pinSizerEntry    = prevPinEntry;        // [v12.1] trả lại trạng thái ghim: Setup sau không bị kẹt ở Entry cũ
      g_pinnedSlDist     = prevPinnedDist;
      if(prevPinEntry)
         g_sizerEntryPrice = prevPinnedEntry;
   }

   if(bookChanged)
      SaveVirtualOrderBookToFile();
   DrawVirtualPendingLine();
}

//+------------------------------------------------------------------+
//| Lưu và Thực thi Virtual TP / Virtual SL trên cả Hedging & Netting|
//+------------------------------------------------------------------+
void SaveVirtualTPForDeal(ulong dealTicket, double targetTP)
{
   if(dealTicket > 0 && targetTP > 0.0 && HistoryDealSelect(dealTicket))
   {
      long positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      if(positionId > 0)
      {
         GlobalVariableSet(VirtualTPPositionKey(positionId), targetTP);
         GlobalVariableSet(AccountScopedGV("EAP82_INITDONE_" + IntegerToString(positionId)), 1.0);
         return;
      }
   }
}

void SaveVirtualTPForLatestPosition(bool isBuy, double targetTP)
{
   if(targetTP <= 0.0)
      return;
   string execSym = GetExecutionSymbol();
   datetime latest = 0;
   long selectedId = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      string s = PositionGetString(POSITION_SYMBOL);
      if(s != _Symbol && s != execSym) continue;
      bool positionBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      if(positionBuy != isBuy) continue;
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      if(opened >= latest)
      {
         latest     = opened;
         selectedId = PositionGetInteger(POSITION_IDENTIFIER);
      }
   }
   if(selectedId > 0)
   {
      GlobalVariableSet(VirtualTPPositionKey(selectedId), targetTP);
      GlobalVariableSet(AccountScopedGV("EAP82_INITDONE_" + IntegerToString(selectedId)), 1.0);
   }
}

void ProcessVirtualTakeProfits()
{
   string execSym = GetExecutionSymbol();
   MqlTick tick;
   if(!SymbolInfoTick(execSym, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string s = PositionGetString(POSITION_SYMBOL);
      if(s != _Symbol && s != execSym) continue;

      long   id  = PositionGetInteger(POSITION_IDENTIFIER);
      string key = VirtualTPPositionKey(id);
      if(!GlobalVariableCheck(key))
         continue;
      double target = GlobalVariableGet(key);
      if(target <= 0.0)
      {
         GlobalVariableDel(key);
         continue;
      }

      bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      string obj   = VIS_PREFIX + "VTP_" + IntegerToString(id);
      if(ObjectFind(0, obj) < 0)
      {
         ObjectCreate(0, obj, OBJ_HLINE, 0, 0, target);
         ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, obj, OBJPROP_SELECTED, true);
         ObjectSetInteger(0, obj, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, obj, OBJPROP_WIDTH, 2);
      }
      ObjectSetDouble(0, obj, OBJPROP_PRICE, 0, target);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, clrGold);
      ObjectSetString(0, obj, OBJPROP_TEXT, StringFormat("V-TP #%I64d @ %s (Kéo thả được)", id, DoubleToString(target, _Digits)));

      bool reached = isBuy ? (tick.bid >= target) : (tick.ask <= target);
      if(reached)
      {
         if(ClosePositionWithConfirmation(ticket))
         {
            GlobalVariableDel(key);
            ObjectDelete(0, obj);
            Alert(StringFormat("TuanProtrade: Đã đóng vị thế #%I64u tại mức TP ảo %s.", ticket, DoubleToString(target, _Digits)));
         }
      }
   }
}

bool SaveVirtualStopForDeal(ulong dealTicket, double targetSL, double emergencySL)
{
   if(dealTicket == 0 || targetSL <= 0.0 || !HistoryDealSelect(dealTicket))
      return false;
   long positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   if(positionId <= 0)
      return false;
   GlobalVariableSet(VirtualSLPositionKey(positionId), targetSL);
   if(emergencySL > 0.0)
      GlobalVariableSet(VirtualEmergencySLPositionKey(positionId), emergencySL);
   GlobalVariableSet(AccountScopedGV("EAP82_INITDONE_" + IntegerToString(positionId)), 1.0);
   return true;
}

void SaveVirtualStopForLatestPosition(bool isBuy, double targetSL, double emergencySL)
{
   string execSym = GetExecutionSymbol();
   datetime latest = 0;
   long selectedId = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string s = PositionGetString(POSITION_SYMBOL);
      if(s != _Symbol && s != execSym) continue;
      bool positionBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      if(positionBuy != isBuy) continue;
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      if(opened >= latest)
      {
         latest     = opened;
         selectedId = PositionGetInteger(POSITION_IDENTIFIER);
      }
   }
   if(selectedId > 0 && targetSL > 0.0)
   {
      GlobalVariableSet(VirtualSLPositionKey(selectedId), targetSL);
      if(emergencySL > 0.0)
         GlobalVariableSet(VirtualEmergencySLPositionKey(selectedId), emergencySL);
      GlobalVariableSet(AccountScopedGV("EAP82_INITDONE_" + IntegerToString(selectedId)), 1.0);
   }
}

void ProcessVirtualStops()
{
   string execSym = GetExecutionSymbol();
   MqlTick tick;
   if(!SymbolInfoTick(execSym, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string s = PositionGetString(POSITION_SYMBOL);
      if(s != _Symbol && s != execSym) continue;

      long   id  = PositionGetInteger(POSITION_IDENTIFIER);
      string key = VirtualSLPositionKey(id);
      if(!GlobalVariableCheck(key))
         continue;
      double target = GlobalVariableGet(key);
      if(target <= 0.0)
      {
         GlobalVariableDel(key);
         continue;
      }

      bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      string obj   = VIS_PREFIX + "VSL_" + IntegerToString(id);
      if(ObjectFind(0, obj) < 0)
      {
         ObjectCreate(0, obj, OBJ_HLINE, 0, 0, target);
         ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, obj, OBJPROP_SELECTED, true);
         ObjectSetInteger(0, obj, OBJPROP_STYLE, STYLE_DASHDOT);
         ObjectSetInteger(0, obj, OBJPROP_WIDTH, 2);
      }
      ObjectSetDouble(0, obj, OBJPROP_PRICE, 0, target);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, clrOrangeRed);
      ObjectSetString(0, obj, OBJPROP_TEXT, StringFormat("V-SL #%I64d @ %s (Backup Server: %s)",
                      id, DoubleToString(target, _Digits), InpEnableEmergencyServerSL ? "ON" : "OFF"));

      bool reached = isBuy ? (tick.bid <= target) : (tick.ask >= target);
      if(reached && ClosePositionWithConfirmation(ticket))
      {
         GlobalVariableDel(key);
         GlobalVariableDel(VirtualEmergencySLPositionKey(id));
         ObjectDelete(0, obj);
         Alert(StringFormat("TuanProtrade: Đã đóng vị thế #%I64u tại mức SL ảo %s.", ticket, DoubleToString(target, _Digits)));
      }
   }
}

// ============================================================================
// MODULE 8: CExternalTradeAdopter (ĐỒNG BỘ LỆNH MOBILE / EA KHÁC 2 CHIỀU)
// ============================================================================

//+------------------------------------------------------------------+
//| Kiểm tra mã Magic của lệnh có thuộc diện lệnh ngoài cần quản lý  |
//+------------------------------------------------------------------+
bool IsExternalMagicMatched(long magic)
{
   if(magic == (long)InpTradeMagicNumber)
      return false;
   if(InpExternalMagicFilter == EXT_FILTER_ALL_EXTERNAL)
      return true;
   if(InpExternalMagicFilter == EXT_FILTER_MANUAL_MOBILE_0)
      return (magic == 0);
   if(InpExternalMagicFilter == EXT_FILTER_CUSTOM_MAGIC)
      return (magic == InpCustomExternalMagic);
   return true;
}

//+------------------------------------------------------------------+
//| Xử lý toàn diện lệnh mở từ MT5 Mobile App / Web / EA Khác:       |
//| 1. Tự gắn SL/TP chuẩn nếu thiếu                                  |
//| 2. Đọc SL tính Risk -> Cắt bớt Lot vượt HOẶC Bồi thêm Lot thiếu  |
//+------------------------------------------------------------------+
void HandleExternalPositionEntry(ulong dealTicket)
{
   if(dealTicket == 0 || !HistoryDealSelect(dealTicket))
      return;

   long   dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(!IsExternalMagicMatched(dealMagic))
      return;

   long   posId  = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   string symbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   string execSym= GetExecutionSymbol();
   if(symbol != _Symbol && symbol != execSym)
      return;

   // Khóa chống xử lý lặp hai lần cho cùng một vị thế ngoại lai
   string adoptDoneKey = AccountScopedGV("TD_ADOPT_DONE_" + IntegerToString(posId));
   if(GlobalVariableCheck(adoptDoneKey))
      return;

   ulong ticket = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong pt = PositionGetTicket(i);
      if(pt > 0 && PositionGetInteger(POSITION_IDENTIFIER) == posId)
      {
         ticket = pt;
         break;
      }
   }
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return;

   if(!g_manageExternalOn)
      return;

   double volume   = PositionGetDouble(POSITION_VOLUME);
   double entry    = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl       = PositionGetDouble(POSITION_SL);
   double tp       = PositionGetDouble(POSITION_TP);
   bool   isBuy    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   string currency = AccountInfoString(ACCOUNT_CURRENCY);

   // Bước 1: Tự động gắn SL/TP cho lệnh Mobile/ngoài chưa có SL/TP nếu được bật
   if((sl <= 0.0 || tp <= 0.0) && (g_attachExternalSlTpOn || g_autoSlTp))
   {
      double calcSl = 0.0, calcTp = 0.0;
      if(GetEntryProtection(isBuy, entry, calcSl, calcTp))
      {
         double applySl = (sl > 0.0) ? sl : calcSl;
         double applyTp = (tp > 0.0) ? tp : calcTp;
         if(ModifyPositionWithConfirmation(ticket, applySl, applyTp))
         {
            sl = applySl;
            tp = applyTp;
            SetToastStatus(StringFormat("Đã tự gắn SL/TP cho lệnh Mobile #%I64u", ticket));
         }
      }
   }

   if(sl <= 0.0)
   {
      AlertThrottled("MOBILE_NO_SL_" + symbol,
                     "TradeDesk Mobile Sync: Phát hiện lệnh ngoài chưa đặt SL; hãy bật Tự gắn SL hoặc đặt SL trên điện thoại để đồng bộ Lot.", 30);
      return;
   }

   // Bước 2: Đọc khoảng cách SL hiện có để tính rủi ro 1 lot và khối lượng mục tiêu chuẩn
   double lossPerLot = 0.0;
   if(!EstimateStopRiskCash(symbol, isBuy, 1.0, entry, sl, g_bufferPts, g_commPerLot, lossPerLot) || lossPerLot <= 0.0)
      return;

   double budget = 0.0;
   string reason = "";
   if(!GetRiskCashBudgetForShare(1.0, budget, reason))
      return;

   if(InpMaxPortfolioRiskPct > 0.0)
   {
      double portfolioRisk = 0.0;
      if(!CalculateAccountExposureRisk(portfolioRisk))
      {
         AlertThrottled("MOBILE_PORTFOLIO_UNKNOWN", "TradeDesk Mobile Sync: Không xác minh được rủi ro danh mục; bỏ qua tự chỉnh lot.", 30);
         return;
      }
      double currentRisk     = lossPerLot * volume;
      double otherRisk       = MathMax(0.0, portfolioRisk - currentRisk);
      double portfolioBudget = MathMax(0.0, GetEffectiveEquity() * InpMaxPortfolioRiskPct / 100.0 - otherRisk);
      budget = MathMin(budget, portfolioBudget);
   }

   double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) step = 0.01;
   int digits = GetStepDigits(step);

   double target = MathFloor((budget / lossPerLot + step * 1e-9) / step) * step;
   target = NormalizeDouble(MathMin(target, maxLot), digits);

   GlobalVariableSet(adoptDoneKey, 1.0);
   GlobalVariableSet(InitialVolKey(posId), MathMax(volume, target));

   // Nhánh 2A: Khối lượng lệnh ngoài VƯỢT ngân sách Risk -> Tự động cắt bớt phần dư
   if(volume > target + step * 0.5)
   {
      if(InpNotifyExternalTrades)
      {
         QueueTradeDeskNotification(StringFormat("TuanProtrade MOBILE OVER-RISK | %s %s | Lot mở %.2f (Risk %.2f %s) > Chuẩn %.2f lot",
                                                 symbol, isBuy ? "BUY" : "SELL", volume, lossPerLot * volume, currency, target), InpTelegramOnOpen);
      }
      if(!g_reduceExternalOn || target < minLot)
         return;

      double excess   = volume - target;
      double closeVol = MathFloor((excess + step * 1e-9) / step) * step;
      closeVol = NormalizeDouble(closeVol, digits);
      if(closeVol < minLot || volume - closeVol < minLot - step * 0.5)
      {
         Alert("TradeDesk Mobile Sync: Phần vượt Risk nhỏ hơn Lot tối thiểu; giữ nguyên vị thế.");
         return;
      }

      double closed = 0.0;
      if(CloseExternalPositionPartially(ticket, closeVol, closed))
      {
         string msg = StringFormat("TuanProtrade MOBILE TRIM | %s | Đã giảm %.2f lot dư; giữ lại %.2f lot đúng chuẩn Risk %.2f %s",
                                   symbol, closed, volume - closed, budget, currency);
         SetToastStatus(msg);
         Alert(msg);
         QueueTradeDeskNotification(msg, InpTelegramOnOpen);
      }
      return;
   }

   // Nhánh 2B: Khối lượng lệnh ngoài NHỎ HƠN ngân sách Risk (Lệnh thăm dò từ Mobile, VD mở 0.02 lot)
   // -> Tự động bồi thêm phần Lot còn thiếu (VD +0.13 lot = 0.15 lot) giống Forex Trade Manager v3.70!
   if(volume < target - step * 0.5 && g_addExternalOn)
   {
      string gateReason = "";
      if(!TradeDeskEntryGate(gateReason))
      {
         Alert("TradeDesk Mobile Sync: Không thể bồi thêm Lot do cổng an toàn: ", gateReason);
         return;
      }

      MqlTick tick;
      if(!SymbolInfoTick(symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
         return;

      double liveFillPx = isBuy ? tick.ask : tick.bid;
      double oneRDist   = MathAbs(entry - sl);
      double slipDist   = MathAbs(liveFillPx - entry);
      if(oneRDist > _Point && (slipDist / oneRDist) * 100.0 > MathMax(1.0, InpMobileSyncMaxSlippagePct1R))
      {
         Alert(StringFormat("TradeDesk Mobile Sync: Giá hiện tại đã chạy lệch quá %.1f%% 1R so với lệnh Mobile; không tự động bồi thêm Lot.",
                            InpMobileSyncMaxSlippagePct1R));
         return;
      }

      double usedRiskCash      = lossPerLot * volume;
      double remainingRiskCash = MathMax(0.0, budget - usedRiskCash);
      double addLot            = 0.0, riskMinAdd = 0.0;
      if(!CalculateSafeVolume(isBuy, liveFillPx, sl, remainingRiskCash, addLot, riskMinAdd) || addLot < minLot)
         return;

      if(g_maxLotPerOrder > 0.0)
         addLot = FloorLotStep(MathMin(addLot, g_maxLotPerOrder));
      if(addLot < minLot)
         return;

      trade.SetExpertMagicNumber((ulong)InpTradeMagicNumber);
      trade.SetDeviationInPoints((ulong)MathMax(0, InpMaxDeviationPoints));
      trade.SetTypeFillingBySymbol(symbol);

      double addTp = (tp > 0.0) ? tp : NormalizePriceToTickSize(symbol, entry + (isBuy ? 1.0 : -1.0) * oneRDist * g_targetRR);
      bool sentAdd = isBuy ? trade.Buy(addLot, symbol, 0.0, sl, addTp, "TradeDesk Mobile Sync Add-on")
                           : trade.Sell(addLot, symbol, 0.0, sl, addTp, "TradeDesk Mobile Sync Add-on");
      if(TradeRequestSucceeded(sentAdd))
      {
         // Đánh dấu vị thế bồi thêm cũng đã hoàn tất đồng bộ để không kích hoạt vòng lặp
         ulong addDeal = trade.ResultDeal();
         if(addDeal > 0 && HistoryDealSelect(addDeal))
         {
            long addPosId = HistoryDealGetInteger(addDeal, DEAL_POSITION_ID);
            if(addPosId > 0)
               GlobalVariableSet(AccountScopedGV("TD_ADOPT_DONE_" + IntegerToString(addPosId)), 1.0);
         }
         string msg = StringFormat("TuanProtrade MOBILE SYNC ADD | %s | Lệnh Mobile %.2fL + Bồi thêm %.2fL = Tổng %.2fL chuẩn Risk %.2f %s",
                                   symbol, volume, addLot, volume + addLot, budget, currency);
         SetToastStatus(msg);
         Alert(msg);
         QueueTradeDeskNotification(msg, InpTelegramOnOpen);
      }
   }
}
// ============================================================================
// MODULE 10: CRiskGuardAndNews (RISK GUARD 3 CHU KỲ, EQUITY PROTECT & LỊCH TIN)
// ============================================================================

//+------------------------------------------------------------------+
//| Sinh hậu tố định danh Tài khoản & Server cho khóa Equity Anchor  |
//+------------------------------------------------------------------+
string GetRiskAccountSuffix()
{
   string server = AccountInfoString(ACCOUNT_SERVER);
   long serverHash = 0;
   for(int i = 0; i < StringLen(server); i++)
      serverHash = (serverHash * 31 + (long)StringGetCharacter(server, i)) % 2147483647;
   return IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + IntegerToString(serverHash);
}

//+------------------------------------------------------------------+
//| Lấy hoặc khởi tạo mốc Equity neo đầu kỳ (Ngày / Tuần / Tháng)    |
//+------------------------------------------------------------------+
double GetOrCreateRiskEquityAnchor(string periodKey, double currentEquity,
                                   double periodTradingPnl, double externalCashFlow)
{
   string key = "EAP83_EQ_" + GetRiskAccountSuffix() + "_" + periodKey;
   if(GlobalVariableCheck(key))
   {
      double saved = GlobalVariableGet(key);
      if(saved > 0.0 && MathIsValidNumber(saved))
         return saved;
   }
   double anchor = currentEquity - periodTradingPnl - externalCashFlow;
   if(anchor <= 0.0 || !MathIsValidNumber(anchor))
      anchor = currentEquity;
   if(anchor > 0.0)
      GlobalVariableSet(key, anchor);
   return anchor;
}

//+------------------------------------------------------------------+
//| Tính PnL 3 chu kỳ Ngày/Tuần/Tháng, Cooldown & Chế độ Phục hồi    |
//+------------------------------------------------------------------+
void CalculateDayWeekMonthPnl(double &outDayPnl, double &outDayPct,
                              double &outWeekPnl, double &outWeekPct,
                              double &outMonthPnl, double &outMonthPct)
{
   outDayPnl   = 0.0; outDayPct   = 0.0;
   outWeekPnl  = 0.0; outWeekPct  = 0.0;
   outMonthPnl = 0.0; outMonthPct = 0.0;

   datetime now = TimeCurrent();
   if(now <= 0) now = TimeTradeServer();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   // Khi bước sang ngày giao dịch mới: làm mới hạn mức dự phòng PIN và dọn rác GV cũ
   if(g_lastDayOfYear != -1 && g_lastDayOfYear != dt.day_of_year)
   {
      g_pinExtraDayPct = 0.0;
      string restoredCycle = "NGÀY MỚI";
      if(dt.day_of_week == 1) { g_pinExtraWeekPct  = 0.0; restoredCycle = "TUẦN MỚI"; }
      if(dt.day == 1)         { g_pinExtraMonthPct = 0.0; restoredCycle = "THÁNG MỚI"; }
      SaveLockStateToGV();
      GarbageCollectOldGVs();

      // Mở khóa Equity Protect nếu đang ở chế độ khóa tới ngày mới
      if(InpEquityProtectPostAction == EQ_ACTION_LOCK_UNTIL_NEXT_DAY &&
         !HasTradesInScope(g_equityScopeAccount) &&
         !GlobalVariableCheck(EquityProtectKey("FLATTEN", g_equityScopeAccount)))
      {
         GlobalVariableSet(EquityProtectKey("LOCK", g_equityScopeAccount), 0.0);
         GlobalVariableDel(EquityProtectKey("PEAK", g_equityScopeAccount));
         // Refresh latch on the next CheckEquityProtect() call.
         g_equityLatched = false;
      }

      if(g_autoSyncDate)
         SyncAnchorDateFields(g_resolvedAtrTf, now);

      if(g_wasBreachedPrev && !g_inCooldownLock)
         NotifyQuotaRestored("KHÔI PHỤC HẠN MỨC " + restoredCycle,
                             "Hạn mức rủi ro đã được làm mới cho chu kỳ giao dịch tiếp theo!");
   }
   g_lastDayOfYear = dt.day_of_year;

   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime startOfDay = StructToTime(dt);

   int daysSinceMonday = (dt.day_of_week == 0) ? 6 : (dt.day_of_week - 1);
   datetime startOfWeek = startOfDay - daysSinceMonday * 86400;

   MqlDateTime dtMonth = dt;
   dtMonth.day = 1; dtMonth.hour = 0; dtMonth.min = 0; dtMonth.sec = 0;
   datetime startOfMonth = StructToTime(dtMonth);

   double closedDay = 0.0, closedWeek = 0.0, closedMonth = 0.0;
   double flowDay   = 0.0, flowWeek   = 0.0, flowMonth   = 0.0;
   datetime earliest = MathMin(startOfMonth, startOfWeek);

   if(!HistorySelect(earliest, now + 60))
   {
      g_riskDataAvailable = false;
      AlertThrottled("RISK_HISTORY_UNAVAILABLE",
                     "Chưa tải xong lịch sử giao dịch MT5; tạm dừng đề xuất Lot để chờ xác minh Risk Guard.");
      return;
   }

   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;
      long     entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      datetime dealTime  = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      long     dealType  = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      double   netPnl    = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                         + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION)
                         + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                         + HistoryDealGetDouble(dealTicket, DEAL_FEE);

      // Tách riêng dòng tiền nạp/rút/credit/bonus khỏi kết quả lãi lỗ giao dịch
      if(dealType == DEAL_TYPE_BALANCE || dealType == DEAL_TYPE_CREDIT ||
         dealType == DEAL_TYPE_BONUS   || dealType == DEAL_TYPE_CORRECTION)
      {
         if(dealTime >= startOfDay)   flowDay   += netPnl;
         if(dealTime >= startOfWeek)  flowWeek  += netPnl;
         if(dealTime >= startOfMonth) flowMonth += netPnl;
         continue;
      }

      bool isTradeExit   = (entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_INOUT || entryType == DEAL_ENTRY_OUT_BY);
      bool isAccountCost = (dealType == DEAL_TYPE_CHARGE || dealType == DEAL_TYPE_INTEREST ||
                            dealType == DEAL_TYPE_COMMISSION || dealType == DEAL_TYPE_COMMISSION_DAILY ||
                            dealType == DEAL_TYPE_COMMISSION_MONTHLY || dealType == DEAL_TYPE_COMMISSION_AGENT_DAILY ||
                            dealType == DEAL_TYPE_COMMISSION_AGENT_MONTHLY);
      if(!isTradeExit && !isAccountCost)
         continue;

      if(dealTime >= startOfDay)   closedDay   += netPnl;
      if(dealTime >= startOfWeek)  closedWeek  += netPnl;
      if(dealTime >= startOfMonth) closedMonth += netPnl;
   }

   double floatingPnl = AccountInfoDouble(ACCOUNT_PROFIT);
   double eq          = GetEffectiveEquity();
   double dayStartEquity = 0.0, weekStartEquity = 0.0, monthStartEquity = 0.0;

   if(g_useLiveEquity && AccountInfoDouble(ACCOUNT_EQUITY) > 0.0)
   {
      double liveEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      string dayId   = TimeToString(startOfDay,   TIME_DATE);
      string weekId  = TimeToString(startOfWeek,  TIME_DATE);
      string monthId = TimeToString(startOfMonth, TIME_DATE);
      StringReplace(dayId,   ".", "");
      StringReplace(weekId,  ".", "");
      StringReplace(monthId, ".", "");

      dayStartEquity   = GetOrCreateRiskEquityAnchor("D_" + dayId,   liveEquity, closedDay   + floatingPnl, flowDay);
      weekStartEquity  = GetOrCreateRiskEquityAnchor("W_" + weekId,  liveEquity, closedWeek  + floatingPnl, flowWeek);
      monthStartEquity = GetOrCreateRiskEquityAnchor("M_" + monthId, liveEquity, closedMonth + floatingPnl, flowMonth);

      outDayPnl   = liveEquity - dayStartEquity   - flowDay;
      outWeekPnl  = liveEquity - weekStartEquity  - flowWeek;
      outMonthPnl = liveEquity - monthStartEquity - flowMonth;
   }
   else
   {
      outDayPnl        = closedDay   + floatingPnl;
      outWeekPnl       = closedWeek  + floatingPnl;
      outMonthPnl      = closedMonth + floatingPnl;
      dayStartEquity   = (eq > 0.0) ? eq : (eq - outDayPnl);
      weekStartEquity  = (eq > 0.0) ? eq : (eq - outWeekPnl);
      monthStartEquity = (eq > 0.0) ? eq : (eq - outMonthPnl);
   }

   // Chống tuyệt đối lỗi hiển thị Th: -100.0% khi mẫu số vốn đầu kỳ chưa hợp lệ
   if(dayStartEquity <= 0.0 || weekStartEquity <= 0.0 || monthStartEquity <= 0.0 ||
      !MathIsValidNumber(dayStartEquity) || !MathIsValidNumber(monthStartEquity))
   {
      g_riskDataAvailable = false;
      outDayPct = 0.0; outWeekPct = 0.0; outMonthPct = 0.0;
      return;
   }

   g_riskDataAvailable = true;
   outDayPct   = (outDayPnl   / dayStartEquity)   * 100.0;
   outWeekPct  = (outWeekPnl  / weekStartEquity)  * 100.0;
   outMonthPct = (outMonthPnl / monthStartEquity) * 100.0;

   double effMaxDay   = g_maxDailyLossPct   + g_pinExtraDayPct;
   double effMaxWeek  = g_maxWeeklyLossPct  + g_pinExtraWeekPct;
   double effMaxMonth = g_maxMonthlyLossPct + g_pinExtraMonthPct;

   if(g_enRiskGuard)   // [v12.1] cảnh báo sớm khi dùng 50/75/90% hạn mức
      CheckRiskQuotaWarnings(outDayPct, outWeekPct, outMonthPct, effMaxDay, effMaxWeek, effMaxMonth);

   bool   rawBreach = false;
   string rawReason = "";

   if(g_enRiskGuard)
   {
      if(effMaxDay > 0.0 && outDayPct <= -effMaxDay)
      { rawBreach = true; rawReason = StringFormat("Quá lỗ NGÀY (%.2f%% <= -%.1f%%)", outDayPct, effMaxDay); }
      else if(effMaxWeek > 0.0 && outWeekPct <= -effMaxWeek)
      { rawBreach = true; rawReason = StringFormat("Quá lỗ TUẦN (%.2f%% <= -%.1f%%)", outWeekPct, effMaxWeek); }
      else if(effMaxMonth > 0.0 && outMonthPct <= -effMaxMonth)
      { rawBreach = true; rawReason = StringFormat("Quá lỗ THÁNG (%.2f%% <= -%.1f%%)", outMonthPct, effMaxMonth); }
   }

   if(rawBreach)
   {
      if(g_breachTimestamp == 0)
      {
         g_breachTimestamp  = now;
         g_inRecoveryMode   = true;
         g_recStartMonthPct = outMonthPct;
         SaveLockStateToGV();
      }
   }

   g_inCooldownLock = false;
   g_cooldownRemSec = 0;
   if(g_enRiskGuard && g_breachTimestamp > 0 && g_cooldownHours > 0.0)
   {
      int elapsedSec  = (int)(now - g_breachTimestamp);
      int requiredSec = (int)MathRound(g_cooldownHours * 3600.0);
      if(elapsedSec < requiredSec)
      {
         g_inCooldownLock = true;
         g_cooldownRemSec = requiredSec - elapsedSec;
      }
      else if(!rawBreach)
      {
         g_breachTimestamp  = 0;
         g_inRecoveryMode   = true;
         g_recStartMonthPct = outMonthPct;
         SaveLockStateToGV();
         NotifyQuotaRestored("HẾT GIỜ HẠ NHIỆT - MỞ KHÓA TÀI KHOẢN",
                             StringFormat("Tài khoản đã được mở khóa trong CHẾ ĐỘ PHỤC HỒI (Risk: %.2f%%/lệnh). Khi lãi đạt +%.1f%% sẽ khôi phục 100%% hạn mức!",
                                          GetActiveRiskPercent(), g_recoveryTargetPct));
      }
   }

   if(g_inRecoveryMode && !rawBreach && !g_inCooldownLock)
   {
      double gainedPct = outMonthPct - g_recStartMonthPct;
      if(gainedPct >= g_recoveryTargetPct)
      {
         g_inRecoveryMode = false;
         SaveLockStateToGV();
         NotifyQuotaRestored("KHÔI PHỤC 100% HẠN MỨC RỦI RO",
                             StringFormat("Chúc mừng! Bạn đã đạt lợi nhuận phục hồi +%.2f%%. Hạn mức Risk/Lệnh đã được khôi phục về 100%% (%.2f%%)!",
                                          gainedPct, g_riskPct));
      }
   }

   bool riskWasBreached = g_riskBreached;
   g_riskBreached = (rawBreach || g_inCooldownLock);
   if(g_riskBreached && !riskWasBreached)
   {
      string shot = InpAutoScreenshotOnTrade ? CaptureChartScreenshot(true, "RISK_LOCK") : "";
      if(InpTelegramOnRiskLock)
         QueueTradeDeskNotification("TuanProtrade RISK LOCK | " + _Symbol + " | " + (rawReason != "" ? rawReason : "đang trong thời gian Cooldown"), true, shot);
   }
   g_wasBreachedPrev = g_riskBreached;

   if(rawBreach)
   {
      if(g_inCooldownLock)
      {
         int h = g_cooldownRemSec / 3600;
         int m = (g_cooldownRemSec % 3600) / 60;
         g_breachReason = StringFormat("%s | Hạ nhiệt %02dg:%02dp", rawReason, h, m);
      }
      else
         g_breachReason = rawReason;
   }
   else if(g_inCooldownLock)
   {
      int h = g_cooldownRemSec / 3600;
      int m = (g_cooldownRemSec % 3600) / 60;
      g_breachReason = StringFormat("KHÓA HẠ NHIỆT (Mở sau %02dg:%02dp)", h, m);
   }
   else
      g_breachReason = "";
}

//+------------------------------------------------------------------+
//| Mở khóa khẩn cấp bằng mã PIN và cấp hạn mức dự phòng (+1.5%)     |
//+------------------------------------------------------------------+
void TryEmergencyPinUnlock()
{
   string cleanPin = g_enteredPinStr;
   StringTrimLeft(cleanPin);
   StringTrimRight(cleanPin);

   string expectedPin = InpUnlockPinCode;
   StringTrimLeft(expectedPin);
   StringTrimRight(expectedPin);
   string customPinKey = AccountScopedGV("TD_CUSTOM_PIN_HASH");

   // Nếu Input PIN để rỗng, cho phép người dùng đặt mã PIN lần đầu tiên trên giao diện
   if(expectedPin == "" && !GlobalVariableCheck(customPinKey))
   {
      if(cleanPin == "" || cleanPin == "****" || StringLen(cleanPin) < 4)
      {
         Alert("TradeDesk PIN: Hãy nhập mã PIN mới (tối thiểu 4 ký tự) vào ô PIN rồi bấm MỞ KHÓA PIN để lưu.");
         return;
      }
      long h = 0;
      for(int i = 0; i < StringLen(cleanPin); i++)
         h = (h * 31 + (long)StringGetCharacter(cleanPin, i)) % 2147483647;
      GlobalVariableSet(customPinKey, (double)h);
      g_enteredPinStr = "****";
      SetToastStatus("Đã thiết lập mã PIN bảo vệ thành công!");
      Alert("TradeDesk PIN: Đã lưu mã PIN bảo vệ mới thành công!");
      return;
   }

   bool pinMatched = false;
   if(expectedPin != "")
      pinMatched = (cleanPin == expectedPin);
   else if(GlobalVariableCheck(customPinKey))
   {
      long h = 0;
      for(int i = 0; i < StringLen(cleanPin); i++)
         h = (h * 31 + (long)StringGetCharacter(cleanPin, i)) % 2147483647;
      pinMatched = ((long)MathRound(GlobalVariableGet(customPinKey)) == h);
   }

   if(!pinMatched)
   {
      SetToastStatus("SAI MÃ PIN! Từ chối mở khóa.");
      Alert("SAI MÃ PIN! Hãy nhập đúng mã PIN bảo vệ để mở khóa khẩn cấp.");
      return;
   }

   double dayPnl, dayPct, weekPnl, weekPct, monthPnl, monthPct;
   CalculateDayWeekMonthPnl(dayPnl, dayPct, weekPnl, weekPct, monthPnl, monthPct);

   if(dayPct <= -(g_maxDailyLossPct + g_pinExtraDayPct))
      g_pinExtraDayPct = MathAbs(dayPct) - g_maxDailyLossPct + InpPinExtraBufferPct;
   if(weekPct <= -(g_maxWeeklyLossPct + g_pinExtraWeekPct))
      g_pinExtraWeekPct = MathAbs(weekPct) - g_maxWeeklyLossPct + InpPinExtraBufferPct;
   if(monthPct <= -(g_maxMonthlyLossPct + g_pinExtraMonthPct))
      g_pinExtraMonthPct = MathAbs(monthPct) - g_maxMonthlyLossPct + InpPinExtraBufferPct;

   g_breachTimestamp  = 0;
   g_inCooldownLock   = false;
   g_riskBreached     = false;
   g_manualForceLock  = false;
   // PIN releases a persistent lock, but never interrupts an unfinished close.
   GlobalVariableSet(EquityProtectKey("LOCK", g_equityScopeAccount), 0.0);
   GlobalVariableSet(EquityProtectKey("LOCK", true), 0.0);
   g_equityLatched = (GlobalVariableCheck(EquityProtectKey("FLATTEN", g_equityScopeAccount)) ||
                      GlobalVariableCheck(EquityProtectKey("FLATTEN", true)));
   g_inRecoveryMode   = true;
   g_recStartMonthPct = monthPct;
   g_enteredPinStr    = "****";

   SaveLockStateToGV();
   RebuildCleanPanel(true);
   ProcessCoreLogic();

   NotifyQuotaRestored("MỞ KHÓA KHẨN CẤP BẰNG MÃ PIN",
                       StringFormat("Đã cấp thêm +%.1f%% hạn mức dự phòng và bật CHẾ ĐỘ PHỤC HỒI (50%% Risk = %.2f%%/lệnh).",
                                    InpPinExtraBufferPct, GetActiveRiskPercent()));
}

//+------------------------------------------------------------------+
//| Equity Protect keys are isolated by account AND affected symbol.|
//| Shared ALL key intentionally covers all charts on the account.  |
//+------------------------------------------------------------------+
string EquityProtectKey(string suffix, bool accountWide)
{
   return AccountScopedGV("TP_EQ_" + suffix + "_" + (accountWide ? "ALL" : GetExecutionSymbol()));
}

//+------------------------------------------------------------------+
//| Equity Protect 2 đầu (Chốt lời nổi tổng & Cắt lỗ nổi / Đỉnh Eq)  |
//| An active flatten instruction survives MT5 restarts and retries.|
//+------------------------------------------------------------------+
void CheckEquityProtect()
{
   string lk = EquityProtectKey("LOCK", g_equityScopeAccount);
   string pk = EquityProtectKey("PEAK", g_equityScopeAccount);
   string fk = EquityProtectKey("FLATTEN", g_equityScopeAccount);
   string allLk = EquityProtectKey("LOCK", true);
   string allFk = EquityProtectKey("FLATTEN", true);

   // First finish any account-wide emergency liquidation even when attached to
   // a different symbol. Never interpret an ALL lock as symbol-only.
   bool allLocked  = GlobalVariableCheck(allLk) && GlobalVariableGet(allLk) > 0.5;
   bool allPending = GlobalVariableCheck(allFk) && GlobalVariableGet(allFk) > 0.5;
   if(allLocked || allPending)
   {
      g_equityLatched = true;
      if(HasTradesInScope(true))
         CloseAllTradesAndOrders("TuanProtrade: tiếp tục đóng lệnh EQUITY toàn tài khoản", true);
      else if(allPending)
         GlobalVariableDel(allFk);
      if(!allLocked && !HasTradesInScope(true))
         g_equityLatched = false;
      return;
   }

   bool localLocked  = GlobalVariableCheck(lk) && GlobalVariableGet(lk) > 0.5;
   bool localPending = GlobalVariableCheck(fk) && GlobalVariableGet(fk) > 0.5;
   if(localLocked || localPending)
   {
      g_equityLatched = true;
      if(HasTradesInScope(g_equityScopeAccount))
         CloseAllTradesAndOrders("TuanProtrade: tiếp tục đóng lệnh EQUITY", g_equityScopeAccount);
      else if(localPending)
         GlobalVariableDel(fk);
      if(!localLocked && !HasTradesInScope(g_equityScopeAccount))
         g_equityLatched = false;
      return;
   }
   g_equityLatched = false;
   if(!g_equityProtectOn)
      return;

   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(eq <= 0.0 || bal <= 0.0)
      return;

   double peak = GlobalVariableCheck(pk) ? GlobalVariableGet(pk) : 0.0;

   // Tính tổng lợi nhuận nổi theo phạm vi (Toàn tài khoản hoặc chỉ Symbol hiện tại)
   string execSym = GetExecutionSymbol();
   double scopeFloatingPnl = 0.0;
   if(g_equityScopeAccount)
      scopeFloatingPnl = AccountInfoDouble(ACCOUNT_PROFIT);
   else
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         string s = PositionGetString(POSITION_SYMBOL);
         if(s == _Symbol || s == execSym)
            scopeFloatingPnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      }
   }

   // Account-wide peak and symbol-specific peak MUST NOT share an equity base.
   // For symbol mode, approximate its equity as Balance + scoped floating P/L.
   double scopedEquity = g_equityScopeAccount ? eq : bal + scopeFloatingPnl;
   if(scopedEquity <= 0.0 || !MathIsValidNumber(scopedEquity))
      return;
   if(peak <= 0.0 || scopedEquity > peak)
   {
      peak = scopedEquity;
      GlobalVariableSet(pk, peak);
   }

   bool   hitLossLimit    = false;
   bool   hitProfitTarget = false;
   string triggerDetail   = "";

   double lossLimitVal    = MathMax(0.0, InpEquityDrawdownPct);
   double profitTargetVal = MathMax(0.0, InpEquityProfitTargetVal);

   if(InpEquityProtectUnit == EQ_UNIT_CASH)
   {
      if(lossLimitVal > 0.0 && scopeFloatingPnl <= -lossLimitVal)
      {
         hitLossLimit  = true;
         triggerDetail = StringFormat("Lỗ nổi chạm -$%.2f (Ngưỡng -$%.2f)", MathAbs(scopeFloatingPnl), lossLimitVal);
      }
      else if(profitTargetVal > 0.0 && scopeFloatingPnl >= profitTargetVal)
      {
         hitProfitTarget = true;
         triggerDetail   = StringFormat("Lãi nổi đạt +$%.2f (Mục tiêu +$%.2f)", scopeFloatingPnl, profitTargetVal);
      }
   }
   else if(InpEquityProtectUnit == EQ_UNIT_BALANCE_PCT)
   {
      double floatPctBal = (scopeFloatingPnl / bal) * 100.0;
      if(lossLimitVal > 0.0 && floatPctBal <= -lossLimitVal)
      {
         hitLossLimit  = true;
         triggerDetail = StringFormat("Lỗ nổi %.2f%% Balance (Ngưỡng -%.2f%%)", floatPctBal, lossLimitVal);
      }
      else if(profitTargetVal > 0.0 && floatPctBal >= profitTargetVal)
      {
         hitProfitTarget = true;
         triggerDetail   = StringFormat("Lãi nổi +%.2f%% Balance (Mục tiêu +%.2f%%)", floatPctBal, profitTargetVal);
      }
   }
   else // EQ_UNIT_EQUITY_PEAK
   {
      if(lossLimitVal > 0.0 && peak > 0.0 && scopedEquity <= peak * (1.0 - lossLimitVal / 100.0))
      {
         hitLossLimit  = true;
         triggerDetail = StringFormat("Equity theo phạm vi $%.2f sụt %.2f%% từ đỉnh $%.2f", scopedEquity, lossLimitVal, peak);
      }
      else if(profitTargetVal > 0.0 && bal > 0.0 && scopedEquity >= bal * (1.0 + profitTargetVal / 100.0))
      {
         hitProfitTarget = true;
         triggerDetail   = StringFormat("Equity theo phạm vi $%.2f tăng +%.2f%% so với Balance $%.2f", scopedEquity, profitTargetVal, bal);
      }
   }

   if(!hitLossLimit && !hitProfitTarget)
      return;

   GlobalVariableSet(fk, 1.0); // Persist intent even on OrderSend rejection/restart.
   g_equityLatched = true;     // Block new entries while liquidation is outstanding.
   if(InpEquityProtectPostAction != EQ_ACTION_CLOSE_ONLY)
      GlobalVariableSet(lk, 1.0);

   CloseAllTradesAndOrders("Equity Protect: " + triggerDetail, g_equityScopeAccount);
   if(!HasTradesInScope(g_equityScopeAccount))
   {
      GlobalVariableDel(fk);
      if(InpEquityProtectPostAction == EQ_ACTION_CLOSE_ONLY)
         g_equityLatched = false;
   }
   if(InpEquityProtectPostAction == EQ_ACTION_CLOSE_ONLY)
      GlobalVariableSet(pk, g_equityScopeAccount ? AccountInfoDouble(ACCOUNT_EQUITY) : bal + scopeFloatingPnl);

   string msg = StringFormat("TuanProtrade EQUITY PROTECT [%s] | %s | Đã kích hoạt đóng lệnh có xác nhận (%s).",
                             hitProfitTarget ? "CHỐT LỜI TỔNG" : "CẮT LỖ NỔI",
                             triggerDetail, g_equityScopeAccount ? "Toàn TK" : _Symbol);
   SetToastStatus(msg);
   Alert(msg);
   string shot = InpAutoScreenshotOnTrade ? CaptureChartScreenshot(true, "EQ_PROTECT") : "";
   if(InpTelegramOnRiskLock)
      QueueTradeDeskNotification(msg, true, shot);
}

//+------------------------------------------------------------------+
//| Bộ lọc Tin tức linh hoạt 3 khung giờ kèm Bitmask thứ trong tuần  |
//+------------------------------------------------------------------+
bool ParseNewsSlotTime(string timeStr, int daysMask, datetime refNow, datetime &outEventTime)
{
   outEventTime = 0;
   string clean = timeStr;
   StringTrimLeft(clean);
   StringTrimRight(clean);
   if(StringLen(clean) < 4 || StringFind(clean, ":") <= 0 || clean == "00:00" || clean == "0:00" || clean == "0")
      return false;

   MqlDateTime day;
   TimeToStruct(refNow, day);
   day.hour = 0; day.min = 0; day.sec = 0;
   datetime today = StructToTime(day);
   long bestDistance = 2147483647;
   datetime bestEvent = 0;

   for(int shift = -1; shift <= 1; shift++)
   {
      datetime candidateDay = today + (datetime)(shift * 86400);
      MqlDateTime cdt;
      TimeToStruct(candidateDay, cdt);
      int dayBit = (cdt.day_of_week == 0) ? 6 : (cdt.day_of_week - 1); // Bit 0 = Thứ Hai .. Bit 6 = Chủ Nhật
      if(daysMask > 0 && ((daysMask & (1 << dayBit)) == 0))
         continue;

      datetime candidate = StringToTime(TimeToString(candidateDay, TIME_DATE) + " " + clean);
      if(candidate <= 0)
         continue;
      long distance = (long)MathAbs((double)(candidate - refNow));
      if(distance < bestDistance)
      {
         bestDistance = distance;
         bestEvent    = candidate;
      }
   }
   outEventTime = bestEvent;
   return (outEventTime > 0);
}

void DrawNewsVerticalLine(string slotName, datetime evServerTime, string labelText, bool isDanger)
{
   string obj = VIS_PREFIX + "NEWS_" + slotName;
   if(evServerTime <= 0)
   {
      ObjectDelete(0, obj);
      return;
   }
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_VLINE, 0, evServerTime, 0);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_BACK, true);
   }
   ObjectSetInteger(0, obj, OBJPROP_TIME, 0, evServerTime);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, isDanger ? clrRed : clrMediumOrchid);
   ObjectSetInteger(0, obj, OBJPROP_STYLE, isDanger ? STYLE_SOLID : STYLE_DOT);
   ObjectSetInteger(0, obj, OBJPROP_WIDTH, isDanger ? 2 : 1);
   ObjectSetString(0, obj, OBJPROP_TEXT, labelText);
}

bool CheckNewsScheduleAndLock(datetime &outActiveWindowStartServer, datetime &outActiveWindowEndServer)
{
   outActiveWindowStartServer = 0;
   outActiveWindowEndServer   = 0;

   if(!g_enNewsFilter)
   {
      g_newsStatusText = "Lọc tin: TẮT";
      DrawNewsVerticalLine("S1", 0, "", false);
      DrawNewsVerticalLine("S2", 0, "", false);
      DrawNewsVerticalLine("S3", 0, "", false);
      return false;
   }

   datetime serverNow = TimeCurrent();
   datetime localNow  = TimeLocal();
   datetime refNow    = (g_newsTz == TZ_LOCAL_PC) ? localNow : serverNow;
   long     tzOffset  = (long)(serverNow - localNow);

   string slots[3]       = { g_newsSlot1,     g_newsSlot2,     g_newsSlot3 };
   bool   slotEnabled[3] = { g_enSlot1,       g_enSlot2,       g_enSlot3 };
   int    slotMasks[3]   = { g_newsDaysMask1, g_newsDaysMask2, g_newsDaysMask3 };

   int    activeSlotCount   = 0;
   bool   inForbiddenWindow = false;
   int    nearestFutureSec  = 999999;
   string nearestSlotStr    = "";
   string activeLockStr     = "";

   for(int i = 0; i < 3; i++)
   {
      string slotId = "S" + IntegerToString(i + 1);
      datetime evTimeRef = 0;

      if(!slotEnabled[i] || !ParseNewsSlotTime(slots[i], slotMasks[i], refNow, evTimeRef))
      {
         DrawNewsVerticalLine(slotId, 0, "", false);
         continue;
      }

      activeSlotCount++;
      int  diffSec    = (int)(evTimeRef - refNow);
      bool slotDanger = (diffSec <= g_minBeforeNews * 60 && diffSec >= -g_minAfterNews * 60);

      datetime evServerTime = (g_newsTz == TZ_LOCAL_PC) ? (evTimeRef + (datetime)tzOffset) : evTimeRef;
      DrawNewsVerticalLine(slotId, evServerTime, "Tin " + IntegerToString(i + 1) + " (" + slots[i] + ")", slotDanger);

      if(slotDanger)
      {
         inForbiddenWindow          = true;
         outActiveWindowStartServer = evServerTime - g_minBeforeNews * 60;
         outActiveWindowEndServer   = evServerTime + g_minAfterNews  * 60;
         activeLockStr = "CẤM TRADE: Đang vướng Tin " + IntegerToString(i + 1) + " (" + slots[i] + ")!";
      }
      else if(diffSec > 0 && diffSec < nearestFutureSec)
      {
         nearestFutureSec = diffSec;
         nearestSlotStr   = "Tin " + IntegerToString(i + 1) + " (" + slots[i] + ")";
      }
   }

   if(activeSlotCount == 0)
      g_newsStatusText = "Tin: Chưa bật khung giờ";
   else if(inForbiddenWindow)
      g_newsStatusText = activeLockStr;
   else if(nearestFutureSec < 999999)
   {
      int mins = nearestFutureSec / 60;
      int secs = nearestFutureSec % 60;
      g_newsStatusText = StringFormat("Bật %d tin | Tới %s (%02dp:%02ds)", activeSlotCount, nearestSlotStr, mins, secs);
   }
   else
      g_newsStatusText = StringFormat("Tin (%d khung): An toàn", activeSlotCount);

   return inForbiddenWindow;
}

//+------------------------------------------------------------------+
//| Hẹn giờ đóng cuối ngày & Lịch giao dịch tuần 5 tác vụ            |
//+------------------------------------------------------------------+
int TimeStampDateKey(datetime value)
{
   MqlDateTime dt;
   TimeToStruct(value, dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

void CheckScheduledFlatten()
{
   if(!g_timeManagerOn)
      return;
   int colon = StringFind(InpTimedFlattenServerTime, ":");
   if(colon <= 0)
      return;
   int hh = (int)StringToInteger(StringSubstr(InpTimedFlattenServerTime, 0, colon));
   int mm = (int)StringToInteger(StringSubstr(InpTimedFlattenServerTime, colon + 1));
   if(hh < 0 || hh > 23 || mm < 0 || mm > 59)
      return;

   datetime now = TimeTradeServer();
   if(now <= 0) now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   if(dt.hour * 60 + dt.min < hh * 60 + mm)
      return;

   string dk = AccountScopedGV("TD_FLAT_" + _Symbol);
   int today = TimeStampDateKey(now);
   if(GlobalVariableCheck(dk) && (int)GlobalVariableGet(dk) == today)
      return;

   GlobalVariableSet(dk, (double)today);
   CloseAllTradesAndOrders("Trade Time Manager: Đóng cuối phiên " + InpTimedFlattenServerTime, false);
}

void ProcessWeeklySchedule()
{
   if(!g_weeklyOn)
      return;

   datetime now = TimeTradeServer();
   if(now <= 0) now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int dayBit  = (dt.day_of_week == 0) ? 6 : (dt.day_of_week - 1);
   int dateKey = TimeStampDateKey(now);

   // Đồng bộ tác vụ 0 với tham số Input chính
   g_timeTasks[0].enabled = g_weeklyOn;

   for(int idx = 0; idx < 5; idx++)
   {
      if(!g_timeTasks[idx].enabled)
         continue;
      if((g_timeTasks[idx].daysMask & (1 << dayBit)) == 0)
         continue;

      int colon = StringFind(g_timeTasks[idx].timeStr, ":");
      if(colon <= 0)
         continue;
      int hh = (int)StringToInteger(StringSubstr(g_timeTasks[idx].timeStr, 0, colon));
      int mm = (int)StringToInteger(StringSubstr(g_timeTasks[idx].timeStr, colon + 1));
      if(hh < 0 || hh > 23 || mm < 0 || mm > 59)
         continue;

      int taskMinuteOfDay = hh * 60 + mm;
      int curMinuteOfDay  = dt.hour * 60 + dt.min;
      // Chỉ thực thi trong cửa sổ 5 phút kể từ thời điểm hẹn giờ để không bắn bù nếu bật máy muộn
      if(curMinuteOfDay < taskMinuteOfDay || curMinuteOfDay > taskMinuteOfDay + 5)
         continue;

      string key = AccountScopedGV(StringFormat("TD_WTASK_%s_%d_%d", _Symbol, idx, (int)g_timeTasks[idx].action));
      if(GlobalVariableCheck(key) && (int)GlobalVariableGet(key) == dateKey)
         continue;

      GlobalVariableSet(key, (double)dateKey);
      g_timeTasks[idx].lastExecDate = dateKey;

      ENUM_WEEKLY_ACTION act = g_timeTasks[idx].action;
      if(act == WEEKLY_OPEN_BUY || act == WEEKLY_OPEN_SELL)
      {
         string reason = "";
         if(!TradeDeskEntryGate(reason))
         {
            Alert(StringFormat("TradeDesk Lịch tuần #%d bị chặn: %s", idx + 1, reason));
            continue;
         }
         int oldMode = g_entryMode;
         ENUM_TRADE_SIDE oldSide = g_tradeSide;
         g_entryMode = ENTRY_MODE_MARKET;
         g_tradeSide = (act == WEEKLY_OPEN_BUY) ? SIDE_LONG : SIDE_SHORT;
         PlaceManualOrder(act == WEEKLY_OPEN_BUY);
         g_entryMode = oldMode;
         g_tradeSide = oldSide;
      }
      else if(act == WEEKLY_CLOSE_SYMBOL)
         CloseAllTradesAndOrders(StringFormat("Lịch tuần #%d (%s)", idx + 1, g_timeTasks[idx].timeStr), false);
      else if(act == WEEKLY_CLOSE_BUY)
         ClosePositionsByFilter(false, false, POSITION_TYPE_BUY, false);
      else if(act == WEEKLY_CLOSE_SELL)
         ClosePositionsByFilter(false, false, POSITION_TYPE_SELL, false);
      else if(act == WEEKLY_DELETE_PENDING)
         CancelTradeDeskPending();

      QueueTradeDeskNotification(StringFormat("TradeDesk WEEKLY TASK #%d | %s | %s | %s",
                                              idx + 1, _Symbol, g_timeTasks[idx].timeStr, EnumToString(act)), InpTelegramOnSchedule);
   }
}

// ============================================================================
// MODULE 12: CJournalAndTelegram (NHẬT KÝ CSV, CHỤP ẢNH & TELEGRAM SENDPHOTO)
// ============================================================================

//+------------------------------------------------------------------+
//| Ghi dòng sự kiện vào tệp nhật ký CSV                             |
//+------------------------------------------------------------------+
void WriteTradeJournalCsvRow(string eventType, ulong ticket, string sideStr, double volume,
                             double entryPrice, double slPrice, double tpPrice, double closePrice,
                             double pointsRes, double netProfitCash, string noteStr)
{
   if(!InpAutoExportJournalCsv)
      return;

   string fileName   = "NhatKy_TradeDeskPro_" + _Symbol + ".csv";
   bool   fileExists = FileIsExist(fileName);
   int    handle     = FileOpen(fileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ';');
   if(handle == INVALID_HANDLE)
      return;

   if(!fileExists || FileSize(handle) == 0)
   {
      FileWrite(handle, "ThoiGian", "Ticket", "CapTien", "KhungATR", "SuKien", "Chieu",
                "Lot", "GiaEntry", "GiaSL", "GiaTP", "GiaDong", "KetQua_Pts", "LaiLo_Tien", "GhiChu");
   }

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle,
             TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES | TIME_SECONDS),
             IntegerToString(ticket),
             _Symbol,
             GetTfShortName(g_resolvedAtrTf),
             eventType,
             sideStr,
             DoubleToString(volume, 2),
             DoubleToString(entryPrice, _Digits),
             DoubleToString(slPrice, _Digits),
             DoubleToString(tpPrice, _Digits),
             DoubleToString(closePrice, _Digits),
             DoubleToString(pointsRes, 0),
             DoubleToString(netProfitCash, 2),
             noteStr);
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Vẽ ghim vị thế đang mở và đường nối lịch sử giao dịch trên chart |
//+------------------------------------------------------------------+
void DrawOrderPinsAndTradingJournal(int openCount, double vwapEntry, bool basketIsLong)
{
   if(!g_showJournal)
   {
      ObjectsDeleteAll(0, JRN_PREFIX);
      return;
   }

   string execSym = GetExecutionSymbol();
   ObjectsDeleteAll(0, JRN_PREFIX + "OPEN_");
   int orderIdx = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string s = PositionGetString(POSITION_SYMBOL);
      if(s != _Symbol && s != execSym)
         continue;

      orderIdx++;
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      double   entry    = PositionGetDouble(POSITION_PRICE_OPEN);
      double   vol      = PositionGetDouble(POSITION_VOLUME);
      double   sl       = SelectedPositionStopForLogic();
      double   tp       = PositionGetDouble(POSITION_TP);
      long     posId    = PositionGetInteger(POSITION_IDENTIFIER);
      bool     isBuy    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

      int      barShift = iBarShift(_Symbol, PERIOD_CURRENT, openTime, false);
      datetime exactBar = (barShift >= 0) ? iTime(_Symbol, PERIOD_CURRENT, barShift) : openTime;
      color    pinClr   = isBuy ? C_BTN_BUY : C_BTN_SELL;

      string gvLoggedOpen = AccountScopedGV("EAP82_JRN_OPEN_" + IntegerToString(posId));
      if(!GlobalVariableCheck(gvLoggedOpen))
      {
         WriteTradeJournalCsvRow("VAO_LENH", ticket, isBuy ? "BUY" : "SELL", vol, entry, sl, tp, 0.0, 0.0, 0.0,
                                 "Khung " + GetTfShortName(g_resolvedAtrTf));
         GlobalVariableSet(gvLoggedOpen, 1.0);
      }

      string vlineName = JRN_PREFIX + "OPEN_VL_" + IntegerToString(ticket);
      double topP = (sl > 0.0 && tp > 0.0) ? MathMax(sl, tp) : (entry + 150 * _Point);
      double botP = (sl > 0.0 && tp > 0.0) ? MathMin(sl, tp) : (entry - 150 * _Point);
      ObjectCreate(0, vlineName, OBJ_TREND, 0, exactBar, botP, exactBar, topP);
      ObjectSetInteger(0, vlineName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, vlineName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, vlineName, OBJPROP_BACK, true);
      ObjectSetInteger(0, vlineName, OBJPROP_COLOR, pinClr);
      ObjectSetInteger(0, vlineName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, vlineName, OBJPROP_STYLE, STYLE_DOT);

      string pinName = JRN_PREFIX + "OPEN_PIN_" + IntegerToString(ticket);
      ObjectCreate(0, pinName, OBJ_TEXT, 0, exactBar, entry);
      ObjectSetString(0, pinName, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetInteger(0, pinName, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, pinName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, pinName, OBJPROP_FONTSIZE, InpFontSize + 1);
      ObjectSetInteger(0, pinName, OBJPROP_COLOR, clrYellow);
      ObjectSetString(0, pinName, OBJPROP_TEXT, "VÀO");

      string lblName = JRN_PREFIX + "OPEN_TXT_" + IntegerToString(ticket);
      string timeStr = TimeToString(openTime, TIME_MINUTES);
      string pinText = StringFormat(" #%d %s %.2f @%s [%s | %s]",
                                    orderIdx, (isBuy ? "BUY" : "SELL"), vol,
                                    DoubleToString(entry, _Digits), timeStr, GetTfShortName(g_resolvedAtrTf));
      ObjectCreate(0, lblName, OBJ_TEXT, 0, exactBar, entry);
      ObjectSetString(0, lblName, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetInteger(0, lblName, OBJPROP_ANCHOR, isBuy ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, lblName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, MathMax(8, InpFontSize - 1));
      ObjectSetInteger(0, lblName, OBJPROP_COLOR, clrYellow);
      ObjectSetString(0, lblName, OBJPROP_TEXT, pinText);

      if(openCount > 1 && g_multiMode == MULTI_BASKET_VWAP && !g_mixedPositionFallback && MathAbs(entry - vwapEntry) > _Point)
      {
         string linkName = JRN_PREFIX + "OPEN_LNK_" + IntegerToString(ticket);
         datetime bar0 = iTime(_Symbol, PERIOD_CURRENT, 0);
         ObjectCreate(0, linkName, OBJ_TREND, 0, exactBar, entry, bar0, vwapEntry);
         ObjectSetInteger(0, linkName, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, linkName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, linkName, OBJPROP_COLOR, pinClr);
         ObjectSetInteger(0, linkName, OBJPROP_STYLE, STYLE_DOT);
      }
   }

   datetime now  = TimeCurrent();
   datetime from = now - MathMax(1, InpJournalHistoryDays) * 86400;
   if(!HistorySelect(from, now + 60))
      return;

   int totalDeals = HistoryDealsTotal();
   for(int d = 0; d < totalDeals; d++)
   {
      ulong dealTicket = HistoryDealGetTicket(d);
      if(dealTicket == 0) continue;
      string dSym = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      if(dSym != _Symbol && dSym != execSym)
         continue;

      long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_INOUT && entryType != DEAL_ENTRY_OUT_BY)
         continue;

      long     posId      = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      datetime outTime    = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      double   outPrice   = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      double   outVol     = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
      long     dealType   = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      bool     wasBuyPos  = (dealType == DEAL_TYPE_SELL);
      double   netCash    = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                          + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION)
                          + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                          + HistoryDealGetDouble(dealTicket, DEAL_FEE);

      datetime inTime  = 0;
      double   inPrice = 0.0;
      for(int k = 0; k < d; k++)
      {
         ulong prevDeal = HistoryDealGetTicket(k);
         if(prevDeal > 0 && HistoryDealGetInteger(prevDeal, DEAL_POSITION_ID) == posId &&
            HistoryDealGetInteger(prevDeal, DEAL_ENTRY) == DEAL_ENTRY_IN)
         {
            inTime  = (datetime)HistoryDealGetInteger(prevDeal, DEAL_TIME);
            inPrice = HistoryDealGetDouble(prevDeal, DEAL_PRICE);
            break;
         }
      }

      double ptsDiff = 0.0;
      if(inPrice > 0.0 && _Point > 0.0)
         ptsDiff = (wasBuyPos ? (outPrice - inPrice) : (inPrice - outPrice)) / _Point;

      string gvDealLogged = AccountScopedGV("EAP82_JRN_DEAL_" + IntegerToString(dealTicket));
      if(!GlobalVariableCheck(gvDealLogged))
      {
         WriteTradeJournalCsvRow("DONG_LENH", dealTicket, wasBuyPos ? "BUY" : "SELL", outVol, inPrice, 0.0, 0.0, outPrice,
                                 ptsDiff, netCash, (netCash >= 0.0 ? "CHOT_LOI" : "CAT_LO"));
         GlobalVariableSet(gvDealLogged, 1.0);
      }

      int      outShift = iBarShift(_Symbol, PERIOD_CURRENT, outTime, false);
      datetime outBar   = (outShift >= 0) ? iTime(_Symbol, PERIOD_CURRENT, outShift) : outTime;
      color    resClr   = (netCash >= 0.0) ? clrLime : clrTomato;

      if(inTime > 0 && inPrice > 0.0)
      {
         int      inShift = iBarShift(_Symbol, PERIOD_CURRENT, inTime, false);
         datetime inBar   = (inShift >= 0) ? iTime(_Symbol, PERIOD_CURRENT, inShift) : inTime;
         string   pathName = JRN_PREFIX + "HIST_PATH_" + IntegerToString(dealTicket);
         if(ObjectFind(0, pathName) < 0)
         {
            ObjectCreate(0, pathName, OBJ_TREND, 0, inBar, inPrice, outBar, outPrice);
            ObjectSetInteger(0, pathName, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, pathName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, pathName, OBJPROP_COLOR, resClr);
            ObjectSetInteger(0, pathName, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, pathName, OBJPROP_STYLE, STYLE_DOT);
         }

         string inPin = JRN_PREFIX + "HIST_IN_" + IntegerToString(dealTicket);
         if(ObjectFind(0, inPin) < 0)
         {
            ObjectCreate(0, inPin, OBJ_TEXT, 0, inBar, inPrice);
            ObjectSetString(0, inPin, OBJPROP_FONT, "Segoe UI Bold");
            ObjectSetInteger(0, inPin, OBJPROP_ANCHOR, ANCHOR_CENTER);
            ObjectSetInteger(0, inPin, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, inPin, OBJPROP_FONTSIZE, InpFontSize);
            ObjectSetInteger(0, inPin, OBJPROP_COLOR, clrAqua);
            ObjectSetString(0, inPin, OBJPROP_TEXT, wasBuyPos ? "▲" : "▼");
         }
      }

      string outBadge = JRN_PREFIX + "HIST_OUT_" + IntegerToString(dealTicket);
      if(ObjectFind(0, outBadge) < 0)
      {
         string outTxt = StringFormat("ĐÓNG %.2f @%s [%+.0f đ | %+$%.2f | %s]",
                                      outVol, DoubleToString(outPrice, _Digits), ptsDiff, netCash, TimeToString(outTime, TIME_MINUTES));
         ObjectCreate(0, outBadge, OBJ_TEXT, 0, outBar, outPrice);
         ObjectSetString(0, outBadge, OBJPROP_FONT, "Segoe UI Bold");
         ObjectSetInteger(0, outBadge, OBJPROP_ANCHOR, ANCHOR_LEFT);
         ObjectSetInteger(0, outBadge, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, outBadge, OBJPROP_FONTSIZE, MathMax(8, InpFontSize - 1));
         ObjectSetInteger(0, outBadge, OBJPROP_COLOR, resClr);
         ObjectSetString(0, outBadge, OBJPROP_TEXT, outTxt);
      }
   }
}

//+------------------------------------------------------------------+
//| Chụp ảnh màn hình biểu đồ và trả về đường dẫn tệp PNG            |
//+------------------------------------------------------------------+
string CaptureChartScreenshot(bool silentMode, string customTag)
{
   long w = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   long h = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(w <= 0 || h <= 0)
   {
      if(!silentMode)
         Alert("TuanProtrade: Không đọc được kích thước biểu đồ để chụp ảnh.");
      return "";
   }
   string stamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   StringReplace(stamp, ".", "");
   StringReplace(stamp, ":", "");
   StringReplace(stamp, " ", "_");

   string safeSymbol = _Symbol;
   StringReplace(safeSymbol, "/", "_");
   StringReplace(safeSymbol, "\\", "_");
   string tagPart  = (customTag != "") ? ("_" + customTag) : "";
   string fileName = "TradeDesk_" + safeSymbol + tagPart + "_" + stamp + ".png";

   int shotW = (int)MathMax(1280, MathMin(1920, w));
   int shotH = (int)MathMax(720,  MathMin(1080, h));
   if(ChartScreenShot(0, fileName, shotW, shotH, ALIGN_RIGHT))
   {
      if(!silentMode)
      {
         SetToastStatus("Đã chụp biểu đồ: " + fileName);
         Alert("TuanProtrade: Đã lưu ảnh biểu đồ vào MQL5/Files/" + fileName);
         if(g_telegramOn && InpTelegramSendPhotoChart)
            QueueTradeDeskNotification("TradeDesk Chart Snapshot | " + _Symbol + " (" + GetTfShortName(_Period) + ")", true, fileName);
      }
      return fileName;
   }
   if(!silentMode)
      Alert("TuanProtrade: Không chụp được biểu đồ; hãy kiểm tra quyền ghi MQL5/Files.");
   return "";
}

//+------------------------------------------------------------------+
//| Các hàm đóng gói HTTP Multipart/Form-Data gửi Ảnh sang Telegram  |
//+------------------------------------------------------------------+
string UrlEncodeTelegramValue(string value)
{
   uchar utf8[];
   int copied = StringToCharArray(value, utf8, 0, WHOLE_ARRAY, CP_UTF8);
   string encoded = "";
   for(int i = 0; i < copied - 1; i++)
   {
      int c = (int)utf8[i];
      bool plain = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
                   c == '-' || c == '_' || c == '.' || c == '~';
      if(plain) encoded += CharToString((uchar)c);
      else      encoded += StringFormat("%%%02X", c);
   }
   return encoded;
}

void AppendStringBytes(uchar &dest[], string text)
{
   uchar utf8[];
   int copied = StringToCharArray(text, utf8, 0, WHOLE_ARRAY, CP_UTF8);
   int addLen = (copied > 0) ? (copied - 1) : 0;
   if(addLen <= 0)
      return;
   int oldSize = ArraySize(dest);
   ArrayResize(dest, oldSize + addLen);
   ArrayCopy(dest, utf8, oldSize, 0, addLen);
}

void AppendRawBytes(uchar &dest[], const uchar &src[], int count)
{
   if(count <= 0)
      return;
   int oldSize = ArraySize(dest);
   ArrayResize(dest, oldSize + count);
   ArrayCopy(dest, src, oldSize, 0, count);
}

bool SendTelegramPhotoMultipart(string photoFile, string caption)
{
   if(photoFile == "" || !FileIsExist(photoFile))
      return false;

   int fh = FileOpen(photoFile, FILE_READ | FILE_BIN);
   if(fh == INVALID_HANDLE)
      return false;
   int fileSize = (int)FileSize(fh);
   if(fileSize <= 0 || fileSize > 10 * 1024 * 1024)
   {
      FileClose(fh);
      return false;
   }
   uchar fileBytes[];
   ArrayResize(fileBytes, fileSize);
   int readBytes = (int)FileReadArray(fh, fileBytes, 0, fileSize);
   FileClose(fh);
   if(readBytes <= 0)
      return false;

   string boundary = "----TradeDeskProBoundary" + IntegerToString((int)GetTickCount());
   uchar  body[];
   ArrayResize(body, 0);

   // Trường 1: chat_id
   AppendStringBytes(body, "--" + boundary + "\r\n");
   AppendStringBytes(body, "Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n");
   AppendStringBytes(body, InpTelegramChatId + "\r\n");

   // Trường 2: caption
   if(caption != "")
   {
      AppendStringBytes(body, "--" + boundary + "\r\n");
      AppendStringBytes(body, "Content-Disposition: form-data; name=\"caption\"\r\n\r\n");
      AppendStringBytes(body, caption + "\r\n");
   }

   // Trường 3: photo (binary PNG)
   AppendStringBytes(body, "--" + boundary + "\r\n");
   AppendStringBytes(body, "Content-Disposition: form-data; name=\"photo\"; filename=\"" + photoFile + "\"\r\n");
   AppendStringBytes(body, "Content-Type: image/png\r\n\r\n");
   AppendRawBytes(body, fileBytes, readBytes);
   AppendStringBytes(body, "\r\n--" + boundary + "--\r\n");

   char   reqData[];
   int    totalBytes = ArraySize(body);
   ArrayResize(reqData, totalBytes);
   for(int i = 0; i < totalBytes; i++)
      reqData[i] = (char)body[i];

   char   response[];
   string responseHeaders = "";
   string headers = "Content-Type: multipart/form-data; boundary=" + boundary + "\r\n";
   string url     = "https://api.telegram.org/bot" + InpTelegramBotToken + "/sendPhoto";

   ResetLastError();
   int status = WebRequest("POST", url, headers, 5000, reqData, response, responseHeaders);
   return (status >= 200 && status < 300);
}

//+------------------------------------------------------------------+
//| Xếp thông báo & ảnh biểu đồ vào hàng đợi gửi bất đồng bộ         |
//+------------------------------------------------------------------+
void QueueTradeDeskNotification(string message, bool telegramEvent, string photoFile)
{
   if(InpAlertOnScreen) Alert(message);
   if(InpAlertEmail)    SendMail("TuanProtrade", message);
   if(InpAlertPush)     SendNotification(StringSubstr(message, 0, 250));
   if(!telegramEvent || !g_telegramOn)
      return;

   int count = ArraySize(g_telegramQueue);
   if(count >= 30)
   {
      for(int i = 1; i < count; i++)
         g_telegramQueue[i - 1] = g_telegramQueue[i];
      count--;
      ArrayResize(g_telegramQueue, count);
   }
   ArrayResize(g_telegramQueue, count + 1);
   g_telegramQueue[count].text      = message;
   g_telegramQueue[count].photoFile = (InpTelegramSendPhotoChart ? photoFile : "");
}

void ProcessTradeDeskNotificationQueue()
{
   if(ArraySize(g_telegramQueue) <= 0)
      return;
   if(!g_telegramOn)
   {
      ArrayResize(g_telegramQueue, 0);
      return;
   }
   if(StringLen(InpTelegramBotToken) < 10 || StringLen(InpTelegramChatId) < 1)
   {
      datetime now = TimeLocal();
      if(g_lastTelegramErrorAt == 0 || now - g_lastTelegramErrorAt >= 60)
      {
         Print("TuanProtrade Telegram: Hãy nhập Bot Token và Chat ID trong Inputs để gửi cảnh báo.");
         g_lastTelegramErrorAt = now;
      }
      ArrayResize(g_telegramQueue, 0);
      return;
   }

   string message   = g_telegramQueue[0].text;
   string photoFile = g_telegramQueue[0].photoFile;

   bool sentOk = false;
   if(photoFile != "" && InpTelegramSendPhotoChart)
   {
      sentOk = SendTelegramPhotoMultipart(photoFile, message);
   }

   if(!sentOk)
   {
      string body = "chat_id=" + UrlEncodeTelegramValue(InpTelegramChatId)
                  + "&text="   + UrlEncodeTelegramValue(message)
                  + "&disable_web_page_preview=true";
      char requestData[];
      int  bytes    = StringToCharArray(body, requestData, 0, WHOLE_ARRAY, CP_UTF8);
      int  dataSize = (bytes > 0) ? (bytes - 1) : 0;
      if(ArrayResize(requestData, dataSize) >= 0)
      {
         char   response[];
         string responseHeaders;
         string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
         string url     = "https://api.telegram.org/bot" + InpTelegramBotToken + "/sendMessage";
         ResetLastError();
         int status = WebRequest("POST", url, headers, 3000, requestData, response, responseHeaders);
         if(status < 200 || status >= 300)
         {
            int err = GetLastError();
            datetime now = TimeLocal();
            if(g_lastTelegramErrorAt == 0 || now - g_lastTelegramErrorAt >= 60)
            {
               Print("TuanProtrade Telegram: Gửi thất bại. HTTP=", status, " error=", err,
                     (status == -1 && err == 4014) ? ". Hãy thêm https://api.telegram.org vào Tools > Options > Expert Advisors > Allow WebRequest." : "");
               g_lastTelegramErrorAt = now;
            }
         }
         else
            sentOk = true;
      }
   }

   for(int i = 1; i < ArraySize(g_telegramQueue); i++)
      g_telegramQueue[i - 1] = g_telegramQueue[i];
   ArrayResize(g_telegramQueue, ArraySize(g_telegramQueue) - 1);
}

//+------------------------------------------------------------------+
//| Cảnh báo phá vỡ vùng Hỗ trợ / Kháng cự (S/R Breakout Alerts)    |
//+------------------------------------------------------------------+
void CheckSupportResistanceBreakout()
{
   if(!g_srAlertsOn)
   {
      g_previousSRBid = 0.0;
      g_previousSRAsk = 0.0;
      return;
   }
   ENUM_TIMEFRAMES tf = (InpSRTimeframe == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpSRTimeframe;
   int lookback = MathMax(3, MathMin(500, InpSRLookbackBars));
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, tf, 1, lookback, rates) < lookback)
      return;

   string execSym = GetExecutionSymbol();
   MqlTick tick;
   if(!SymbolInfoTick(execSym, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      return;

   double resistance = rates[0].high, support = rates[0].low;
   for(int i = 1; i < lookback; i++)
   {
      resistance = MathMax(resistance, rates[i].high);
      support    = MathMin(support,    rates[i].low);
   }
   double   buffer     = MathMax(0, InpSRBreakBufferPoints) * _Point;
   datetime currentBar = iTime(_Symbol, tf, 0);

   if(g_previousSRBid > 0.0 && g_previousSRBid <= resistance + buffer && tick.bid > resistance + buffer && g_lastSRSignalBar != currentBar)
   {
      g_lastSRSignalBar = currentBar;
      string shot = (InpAutoScreenshotOnTrade && InpTelegramSendPhotoChart) ? CaptureChartScreenshot(true, "SR_UP") : "";
      QueueTradeDeskNotification(StringFormat("TradeDesk S/R BREAKOUT UP | %s %s | Kháng cự %s bị phá, giá %s",
                                              _Symbol, GetTfShortName(tf), DoubleToString(resistance, _Digits), DoubleToString(tick.bid, _Digits)),
                                 InpTelegramOnSR, shot);
   }
   else if(g_previousSRAsk > 0.0 && g_previousSRAsk >= support - buffer && tick.ask < support - buffer && g_lastSRSignalBar != currentBar)
   {
      g_lastSRSignalBar = currentBar;
      string shot = (InpAutoScreenshotOnTrade && InpTelegramSendPhotoChart) ? CaptureChartScreenshot(true, "SR_DOWN") : "";
      QueueTradeDeskNotification(StringFormat("TradeDesk S/R BREAKDOWN | %s %s | Hỗ trợ %s bị phá, giá %s",
                                              _Symbol, GetTfShortName(tf), DoubleToString(support, _Digits), DoubleToString(tick.ask, _Digits)),
                                 InpTelegramOnSR, shot);
   }
   g_previousSRBid = tick.bid;
   g_previousSRAsk = tick.ask;
}

// ============================================================================
// [PATCH v12.1] KHỐI A - CÁC HÀM MỚI (dán 1 lần, ngay TRƯỚC dòng chú thích
// "Cầu nối Chỉ báo Ngoài (STTS / Smart Universal EA Signal Bridge)")
// ============================================================================

//+------------------------------------------------------------------+
//| Point của symbol THỰC THI (tránh dùng _Point của chart Renko)    |
//+------------------------------------------------------------------+
double ExecPoint()
{
   double p = SymbolInfoDouble(GetExecutionSymbol(), SYMBOL_POINT);
   return (p > 0.0) ? p : _Point;
}

//+------------------------------------------------------------------+
//| Đưa tin vào hàng đợi Telegram, KHÔNG bật Alert/Push/Mail         |
//+------------------------------------------------------------------+
void TgEnqueueOnly(string message, string photoFile)
{
   if(!g_telegramOn)
      return;
   int count = ArraySize(g_telegramQueue);
   if(count >= 30)
   {
      for(int i = 1; i < count; i++)
         g_telegramQueue[i - 1] = g_telegramQueue[i];
      count--;
      ArrayResize(g_telegramQueue, count);
   }
   ArrayResize(g_telegramQueue, count + 1);
   g_telegramQueue[count].text      = message;
   g_telegramQueue[count].photoFile = (InpTelegramSendPhotoChart ? photoFile : "");
}

// ============================================================================
// GlobalVariable: bảo vệ PIN / mask khỏi bị dọn rác & hết hạn 4 tuần
// ============================================================================

//+------------------------------------------------------------------+
//| id có phải ticket/identifier của vị thế hoặc lệnh chờ đang sống? |
//+------------------------------------------------------------------+
bool IsLiveTicketOrId(long id)
{
   if(id <= 0)
      return false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if((long)tk == id || PositionGetInteger(POSITION_IDENTIFIER) == id)
         return true;
   }
   for(int j = OrdersTotal() - 1; j >= 0; j--)
   {
      ulong ot = OrderGetTicket(j);
      if(ot != 0 && (long)ot == id)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| GV có thuộc nhóm KHÔNG được xóa không?                           |
//+------------------------------------------------------------------+
bool IsProtectedGVName(string name)
{
   if(StringFind(name, "TD_CUSTOM_PIN_HASH") >= 0 || StringFind(name, "TP_OCO_ABORT_") >= 0)
      return true;
   if(StringFind(name, "_LK_") >= 0 || StringFind(name, "_EQ_") >= 0 || StringFind(name, "_PROFILE_") >= 0)
      return true;

   // Khóa có đuôi _<ticket/positionId> của lệnh/vị thế còn sống (mask Partial, BE, SL/TP ảo...)
   int len = StringLen(name);
   int us  = -1;
   for(int i = len - 1; i >= 0; i--)
   {
      if(StringGetCharacter(name, i) == '_')
      {
         us = i;
         break;
      }
   }
   if(us > 0 && us < len - 1)
   {
      string tail = StringSubstr(name, us + 1);
      long   id   = StringToInteger(tail);
      if(id > 0 && IntegerToString(id) == tail && IsLiveTicketOrId(id))
         return true;
   }
   return false;
}

void TouchGV(string key)
{
   if(GlobalVariableCheck(key))
      GlobalVariableSet(key, GlobalVariableGet(key));   // Set lại cùng giá trị để làm mới "thời điểm truy cập cuối"
}

//+------------------------------------------------------------------+
//| Làm mới thời điểm truy cập của các GV quan trọng (6 giờ / lần)   |
//+------------------------------------------------------------------+
void TouchCriticalGlobals()
{
   static datetime s_lastTouch = 0;
   datetime now = TimeLocal();
   if(s_lastTouch != 0 && now - s_lastTouch < 6 * 3600)
      return;
   s_lastTouch = now;

   TouchGV(AccountScopedGV("TD_CUSTOM_PIN_HASH"));
   TouchGV(EquityProtectKey("LOCK", g_equityScopeAccount));
   TouchGV(EquityProtectKey("PEAK", g_equityScopeAccount));
   TouchGV(EquityProtectKey("FLATTEN", g_equityScopeAccount));
   TouchGV(EquityProtectKey("LOCK", true));
   TouchGV(EquityProtectKey("FLATTEN", true));
   TouchGV(AccountScopedGV("TP_OCO_ABORT_" + GetExecutionSymbol()));

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      long pid = PositionGetInteger(POSITION_IDENTIFIER);
      TouchGV(PartialTpMaskKey(pid));
      TouchGV(PartialSlMaskKey(pid));
      TouchGV(StepBeMaskKey(pid));
      TouchGV(InitialVolKey(pid));
      TouchGV(VirtualSLPositionKey(pid));
      TouchGV(VirtualEmergencySLPositionKey(pid));
      TouchGV(VirtualTPPositionKey(pid));
   }
}

// ============================================================================
// TELEGRAM: THẺ TÍN HIỆU STTS
// ============================================================================

//+------------------------------------------------------------------+
//| [v12.1.1] Báo cáo cấu hình Telegram khi khởi động (Experts + Tele)|
//+------------------------------------------------------------------+
void TelegramStartupReport()
{
   string bridge = (g_sttsBridgeMode == STTS_BRIDGE_OFF) ? "TẮT"
                   : ((g_sttsBridgeMode == STTS_BRIDGE_AUTO_SIGNAL) ? "AUTO_SIGNAL" : "FILTER_HUD");
   Print(StringFormat("TuanProtrade Telegram: bật=%s | Token=%s | ChatId=%s | Cầu nối STTS=%s | Cảnh báo rủi ro=%s (mốc %s%%)",
                      g_telegramOn ? "CÓ" : "KHÔNG",
                      (StringLen(InpTelegramBotToken) >= 10) ? "đã nhập" : "CHƯA NHẬP",
                      (StringLen(InpTelegramChatId) >= 1) ? "đã nhập" : "CHƯA NHẬP",
                      bridge, InpRiskWarnEnabled ? "BẬT" : "TẮT", InpRiskWarnLevels));
   if(!g_telegramOn)
   {
      Print("TuanProtrade Telegram: ĐANG TẮT. Hãy đặt InpTelegramEnabled = true (hoặc bấm nút TG: ON ở tab 5. SETTINGS).");
      return;
   }
   if(StringLen(InpTelegramBotToken) < 10 || StringLen(InpTelegramChatId) < 1)
   {
      Print("TuanProtrade Telegram: Thiếu Bot Token hoặc Chat ID trong Inputs.");
      return;
   }
   TgEnqueueOnly(StringFormat("TuanProtrade.1 ONLINE | %s %s | TK #%I64d\nTrạng thái: %s\nCầu nối STTS: %s | Cảnh báo rủi ro: %s",
                              _Symbol, GetTfShortName(_Period), AccountInfoInteger(ACCOUNT_LOGIN),
                              g_accountSwitchHold ? "CHỜ XÁC NHẬN TÀI KHOẢN (EA tạm dừng)" : "SẴN SÀNG",
                              bridge, InpRiskWarnEnabled ? "BẬT" : "TẮT"), "");
}

//+------------------------------------------------------------------+
//| Gửi thẻ tín hiệu (hướng, giá, kế hoạch SL/TP, lot, trạng thái)   |
//+------------------------------------------------------------------+
void SendSttsSignalCard(bool isBuy)
{
   string  execSym = GetExecutionSymbol();
   int     digs    = (int)SymbolInfoInteger(execSym, SYMBOL_DIGITS);
   MqlTick tk;
   double  px = 0.0;
   if(SymbolInfoTick(execSym, tk))
      px = isBuy ? tk.ask : tk.bid;

   string msg = StringFormat("TradeDesk TÍN HIỆU %s | %s (%s)\nGiá hiện tại: %s",
                             isBuy ? "MUA (BUY)" : "BÁN (SELL)", _Symbol, GetTfShortName(_Period),
                             DoubleToString(px, digs));

   bool sameSide = ((g_tradeSide == SIDE_LONG) == isBuy);
   if(sameSide && g_sizerEntryPrice > 0.0 && g_sizerSlPrice > 0.0)
   {
      double dist = MathAbs(g_sizerEntryPrice - g_sizerSlPrice);
      msg += StringFormat("\nKế hoạch (Sizer): Entry %s | SL %s",
                          DoubleToString(g_sizerEntryPrice, digs), DoubleToString(g_sizerSlPrice, digs));
      if(g_sizerTpPrice > 0.0 && dist > 0.0)
         msg += StringFormat(" | TP %s | R:R 1:%.2f", DoubleToString(g_sizerTpPrice, digs),
                             MathAbs(g_sizerTpPrice - g_sizerEntryPrice) / dist);
      if(g_nextAddOnSuggestedLot > 0.0)
         msg += StringFormat("\nLot gợi ý cho lệnh kế tiếp: %.2f", g_nextAddOnSuggestedLot);
   }
   else
      msg += "\nKế hoạch: chưa có SL/TP cho hướng này (Sizer đang ở hướng ngược hoặc chưa tạo Setup).";

   msg += StringFormat("\nRisk/lệnh: %.2f%%", GetActiveRiskPercent());

   string gateReason = "";
   if(TradeDeskEntryGate(gateReason))
      msg += "\nCổng an toàn: SẴN SÀNG";
   else
      msg += "\nCổng an toàn: CHẶN - " + gateReason;

   string shot = InpTelegramSendPhotoChart ? CaptureChartScreenshot(true, "STTS_" + (isBuy ? "BUY" : "SELL")) : "";
   QueueTradeDeskNotification(msg, InpTelegramOnSignal, shot);
}

// ============================================================================
// TELEGRAM: CẢNH BÁO RỦI RO
// ============================================================================

double g_riskWarnLevels[];
string g_riskWarnLevelsSrc = "#";

void ParseRiskWarnLevels()
{
   ArrayResize(g_riskWarnLevels, 0);
   string parts[];
   int n = StringSplit(InpRiskWarnLevels, ',', parts);
   for(int i = 0; i < n; i++)
   {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      double v = StringToDouble(p);
      if(v > 0.0 && v < 100.0)
      {
         int c = ArraySize(g_riskWarnLevels);
         ArrayResize(g_riskWarnLevels, c + 1);
         g_riskWarnLevels[c] = v;
      }
   }
   if(ArraySize(g_riskWarnLevels) > 1)
      ArraySort(g_riskWarnLevels);
}

//+------------------------------------------------------------------+
//| Cảnh báo 1 chu kỳ (slot 0=Ngày, 1=Tuần, 2=Tháng) khi dùng X% quota|
//+------------------------------------------------------------------+
void CheckOnePeriodQuota(int slot, string label, double pct, double maxPct, datetime periodKey)
{
   static datetime s_key[3];
   static int      s_hit[3];

   if(s_key[slot] != periodKey)
   {
      s_key[slot] = periodKey;
      s_hit[slot] = 0;
   }
   if(maxPct <= 0.0 || pct >= 0.0)
   {
      if(pct >= 0.0)
         s_hit[slot] = 0;
      return;
   }

   double used = (-pct / maxPct) * 100.0;
   int    nLv  = ArraySize(g_riskWarnLevels);
   int    idx  = 0;
   for(int i = 0; i < nLv; i++)
   {
      if(used >= g_riskWarnLevels[i])
         idx = i + 1;
   }

   if(idx > s_hit[slot])
   {
      s_hit[slot] = idx;
      double remainPct  = MathMax(0.0, maxPct + pct);
      double remainCash = GetEffectiveEquity() * remainPct / 100.0;
      QueueTradeDeskNotification(
         StringFormat("TradeDesk CẢNH BÁO RỦI RO %s | %s | Đã dùng %.0f%% hạn mức (%.2f%% / -%.1f%%) | Còn lại %.2f%% (~%.2f %s)",
                      label, _Symbol, used, pct, maxPct, remainPct, remainCash, AccountInfoString(ACCOUNT_CURRENCY)),
         InpTelegramOnRiskWarn, "");
   }
   else if(idx < s_hit[slot] && s_hit[slot] > 0 && used < g_riskWarnLevels[s_hit[slot] - 1] - 5.0)
      s_hit[slot] = idx;   // Quay về vùng an toàn thì cho phép cảnh báo lại
}

//+------------------------------------------------------------------+
//| Gọi từ CalculateDayWeekMonthPnl sau khi đã có % và hạn mức hiệu lực|
//+------------------------------------------------------------------+
void CheckRiskQuotaWarnings(double dayPct, double weekPct, double monthPct,
                            double maxDay, double maxWeek, double maxMonth)
{
   if(!InpRiskWarnEnabled)
      return;
   if(g_riskWarnLevelsSrc != InpRiskWarnLevels)
   {
      g_riskWarnLevelsSrc = InpRiskWarnLevels;
      ParseRiskWarnLevels();
   }
   if(ArraySize(g_riskWarnLevels) == 0)
      return;

   CheckOnePeriodQuota(0, "NGÀY",  dayPct,   maxDay,   iTime(_Symbol, PERIOD_D1,  0));
   CheckOnePeriodQuota(1, "TUẦN",  weekPct,  maxWeek,  iTime(_Symbol, PERIOD_W1,  0));
   CheckOnePeriodQuota(2, "THÁNG", monthPct, maxMonth, iTime(_Symbol, PERIOD_MN1, 0));
}

//+------------------------------------------------------------------+
//| Cảnh báo Margin Level thấp & vị thế không có SL (gọi trong OnTimer)|
//+------------------------------------------------------------------+
void CheckAccountRiskWarnings()
{
   if(!InpRiskWarnEnabled)
      return;
   static datetime s_lastRun = 0;
   datetime now = TimeLocal();
   if(s_lastRun != 0 && now - s_lastRun < 5)
      return;
   s_lastRun = now;

   // ---- 1) Margin Level ----
   static int s_marginState = 0;   // 0 = ổn, 1 = thấp, 2 = sát mức Stop-Out
   double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(PositionsTotal() <= 0 || ml <= 0.0)
      s_marginState = 0;
   else
   {
      double soLevel   = AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);
      bool   soPercent = (AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE) == ACCOUNT_STOPOUT_MODE_PERCENT);
      double critical  = (soPercent && soLevel > 0.0) ? soLevel * 1.25 : 0.0;

      int newState = 0;
      if(critical > 0.0 && ml <= critical)
         newState = 2;
      else if(InpMarginLevelWarnPct > 0.0 && ml < InpMarginLevelWarnPct)
         newState = 1;

      if(newState > s_marginState)
      {
         s_marginState = newState;
         QueueTradeDeskNotification(
            StringFormat("TradeDesk %s | Margin Level %.1f%% | Equity %.2f %s | Stop-Out %.0f%%",
                         (newState == 2) ? "CẢNH BÁO NGUY HIỂM: SÁT MỨC STOP-OUT" : "CẢNH BÁO: MARGIN LEVEL THẤP",
                         ml, AccountInfoDouble(ACCOUNT_EQUITY), AccountInfoString(ACCOUNT_CURRENCY), soLevel),
            InpTelegramOnRiskWarn, "");
      }
      else if(newState < s_marginState)
      {
         double upper = (s_marginState == 2) ? critical : InpMarginLevelWarnPct;
         if(ml > upper * 1.1)
            s_marginState = newState;
      }
   }

   // ---- 2) Vị thế không có SL (cứng lẫn ảo) ----
   if(InpNakedPosWarnSec <= 0)
      return;
   static string s_nakedSeen = "|";
   string execSym  = GetExecutionSymbol();
   string nakedNow = "|";
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      string s = PositionGetString(POSITION_SYMBOL);
      if(s != _Symbol && s != execSym) continue;
      if(PositionGetDouble(POSITION_SL) > 0.0) continue;
      long pid = PositionGetInteger(POSITION_IDENTIFIER);
      if(GlobalVariableCheck(VirtualSLPositionKey(pid))) continue;
      if(TimeCurrent() - (datetime)PositionGetInteger(POSITION_TIME) < InpNakedPosWarnSec) continue;

      nakedNow += IntegerToString((long)tk) + "|";
      if(StringFind(s_nakedSeen, "|" + IntegerToString((long)tk) + "|") < 0)
      {
         bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         double vol   = PositionGetDouble(POSITION_VOLUME);
         double open  = PositionGetDouble(POSITION_PRICE_OPEN);
         QueueTradeDeskNotification(
            StringFormat("TradeDesk CẢNH BÁO: VỊ THẾ KHÔNG CÓ SL | %s %s %.2f lot @ %s | ticket #%I64u",
                         s, isBuy ? "BUY" : "SELL", vol,
                         DoubleToString(open, (int)SymbolInfoInteger(s, SYMBOL_DIGITS)), tk),
            InpTelegramOnRiskWarn, "");
      }
   }
   s_nakedSeen = nakedNow;
}

//+------------------------------------------------------------------+
//| Cầu nối Chỉ báo Ngoài (STTS / Smart Universal EA Signal Bridge)  |
//| [v12.1] Có hết hạn xu hướng, thẻ tín hiệu Telegram, tự vào lệnh  |
//+------------------------------------------------------------------+
void CheckExternalSignalBridge()
{
   if(g_sttsBridgeMode == STTS_BRIDGE_OFF || InpExtIndicatorName == "")
   {
      g_sttsCurrentTrend = 0;
      g_sttsTrendSetBar  = 0;
      return;
   }

   if(g_sttsIndicatorHandle == INVALID_HANDLE)
   {
      g_sttsIndicatorHandle = iCustom(_Symbol, _Period, InpExtIndicatorName);
      if(g_sttsIndicatorHandle == INVALID_HANDLE)
      {
         // [v12.1.1] Báo lỗi rõ ràng (mỗi 60 giây) thay vì im lặng
         static datetime s_lastIndWarn = 0;
         if(s_lastIndWarn == 0 || TimeLocal() - s_lastIndWarn >= 60)
         {
            s_lastIndWarn = TimeLocal();
            Print("TradeDesk STTS Bridge: KHÔNG nạp được chỉ báo '", InpExtIndicatorName, "' (lỗi ", GetLastError(),
                  "). Kiểm tra đường dẫn tên chỉ báo trong MQL5\\Indicators, ví dụ Market\\Ten Chi Bao.");
         }
         return;
      }
   }

   datetime closedBar = iTime(_Symbol, _Period, 1);
   if(closedBar <= 0)
      return;

   double buyBuf[], sellBuf[];
   ArraySetAsSeries(buyBuf,  true);
   ArraySetAsSeries(sellBuf, true);

   bool hasBuy  = (CopyBuffer(g_sttsIndicatorHandle, MathMax(0, InpExtBuyBufferIdx),  1, 1, buyBuf)  == 1 && buyBuf[0]  > 0.0 && buyBuf[0]  != EMPTY_VALUE);
   bool hasSell = (CopyBuffer(g_sttsIndicatorHandle, MathMax(0, InpExtSellBufferIdx), 1, 1, sellBuf) == 1 && sellBuf[0] > 0.0 && sellBuf[0] != EMPTY_VALUE);

   if(hasBuy && !hasSell)
   {
      g_sttsCurrentTrend = 1;
      g_sttsTrendSetBar  = closedBar;
   }
   else if(hasSell && !hasBuy)
   {
      g_sttsCurrentTrend = -1;
      g_sttsTrendSetBar  = closedBar;
   }

   // [v12.1] Xu hướng tự về Trung lập (0) nếu quá N nến không có tín hiệu mới
   if(g_sttsCurrentTrend != 0 && InpSttsTrendExpireBars > 0 && g_sttsTrendSetBar > 0)
   {
      int age = iBarShift(_Symbol, _Period, g_sttsTrendSetBar, false);
      if(age < 0 || age > InpSttsTrendExpireBars)
      {
         g_sttsCurrentTrend = 0;
         g_sttsTrendSetBar  = 0;
      }
   }

   if((hasBuy || hasSell) && closedBar != g_lastSttsSignalBar)
   {
      g_lastSttsSignalBar = closedBar;
      if(hasBuy && hasSell)
      {
         Print("TradeDesk STTS Bridge: Buffer MUA và BÁN cùng có tín hiệu trên một nến, bỏ qua.");
         return;
      }

      bool   isBuy   = hasBuy;
      string sigSide = isBuy ? "BUY" : "SELL";
      SetToastStatus("Tín hiệu STTS Bridge: " + sigSide + " trên " + _Symbol);

      if(g_sttsBridgeMode == STTS_BRIDGE_AUTO_SIGNAL)
      {
         SendSttsSignalCard(isBuy);

         // [v12.1] Chỉ tự vào lệnh khi người dùng bật InpSttsAutoExecute (mặc định TẮT)
         if(InpSttsAutoExecute)
         {
            string gateReason = "";
            if(!TradeDeskEntryGate(gateReason))
               Print("TradeDesk STTS AUTO: bị chặn bởi cổng an toàn - ", gateReason);
            else if(CountPositionsInScope(false) > 0)
               Print("TradeDesk STTS AUTO: bỏ qua vì đang có vị thế trên Symbol.");
            else
               PlaceManualOrder(isBuy);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Chuyển đổi nhanh Symbol (Hỗ trợ đồng bộ mọi biểu đồ đang mở)     |
//+------------------------------------------------------------------+
void SwitchChartSymbol(int direction)
{
   int total = SymbolsTotal(true);
   if(total < 2)
   {
      Alert("TuanProtrade: Cần ít nhất 2 Symbol trong Market Watch để chuyển nhanh.");
      return;
   }
   int current = -1;
   for(int i = 0; i < total; i++)
   {
      if(SymbolName(i, true) == _Symbol)
      {
         current = i;
         break;
      }
   }
   if(current < 0) current = 0;
   int next = current;
   for(int n = 0; n < total; n++)
   {
      next = (next + (direction >= 0 ? 1 : -1) + total) % total;
      string candidate = SymbolName(next, true);
      if(candidate != "" && SymbolSelect(candidate, true))
      {
         if(InpSyncSymbolAllCharts)
         {
            long chId = ChartFirst();
            while(chId >= 0)
            {
               if(chId != ChartID())
                  ChartSetSymbolPeriod(chId, candidate, ChartPeriod(chId));
               chId = ChartNext(chId);
            }
         }
         if(ChartSetSymbolPeriod(0, candidate, (ENUM_TIMEFRAMES)_Period))
            return;
      }
   }
   Alert("TuanProtrade: Không đổi được sang Symbol tiếp theo trong Market Watch.");
}

// ============================================================================
// BỘ ĐIỀU PHỐI TRUNG TÂM PROCESSCORELOGIC (HỢP NHẤT TOÀN BỘ MODULE QUA ARBITER)
// ============================================================================

void UpdateAccountSwitchHoldDisplay(double dayPct, double weekPct, double monthPct)
{
   string dataText = g_accountHoldRiskDataReady ? "DỮ LIỆU RISK ĐÃ TẢI" : "ĐANG TẢI LỊCH SỬ RISK";
   string hud = StringFormat("CẦN XÁC NHẬN TÀI KHOẢN/LỆNH — EA TẠM DỪNG | %s | N:%.1f%% T:%.1f%% Th:%.1f%%",
                             dataText, dayPct, weekPct, monthPct);
   if(ObjectFind(0, PREFIX + "Hud_Line1") >= 0)
   {
      ObjectSetString(0, PREFIX + "Hud_Line1", OBJPROP_TEXT, hud);
      ObjectSetInteger(0, PREFIX + "Hud_Line1", OBJPROP_COLOR, clrOrangeRed);
   }
   if(ObjectFind(0, PREFIX + "Btn_ForceLock") >= 0)
   {
      ObjectSetString(0, PREFIX + "Btn_ForceLock", OBJPROP_TEXT,
                      g_accountHoldRiskDataReady ? "XÁC NHẬN TK" : "CHỜ DỮ LIỆU");
      ObjectSetInteger(0, PREFIX + "Btn_ForceLock", OBJPROP_BGCOLOR,
                       g_accountHoldRiskDataReady ? C_BTN_ACT : C_BTN_LOCK);
   }
   if(ObjectFind(0, PREFIX + "Hud_Line2R") >= 0)
      ObjectSetString(0, PREFIX + "Hud_Line2R", OBJPROP_TEXT, "Kiểm tra vị thế, SL/TP trước khi xác nhận tiếp tục.");
   if(ObjectFind(0, PREFIX + "Hud_Line3R") >= 0)
      ObjectSetString(0, PREFIX + "Hud_Line3R", OBJPROP_TEXT, "EA không gửi lệnh khi đang tạm dừng.");
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Chu trình xử lý lõi: Thu thập trạng thái -> Tính toán -> Arbiter |
//+------------------------------------------------------------------+
void ProcessCoreLogic()
{
   double dayPnl, dayPct, weekPnl, weekPct, monthPnl, monthPct;
   CalculateDayWeekMonthPnl(dayPnl, dayPct, weekPnl, weekPct, monthPnl, monthPct);

   if(g_accountSwitchHold)
   {
      g_accountHoldRiskDataReady = g_riskDataAvailable;
      UpdateAccountSwitchHoldDisplay(dayPct, weekPct, monthPct);
      return;
   }

   // Ưu tiên P1: Đóng cưỡng bức do Risk Guard hoặc Khóa tay
   bool accountWideRiskAction = g_manualForceLock || (InpRiskControlScope == SCOPE_ACCOUNT);
   if((g_riskBreached || g_manualForceLock) && HasTradesInScope(accountWideRiskAction))
   {
      string msg = g_manualForceLock ? "Đang bật khóa thủ công" : g_breachReason;
      CloseAllTradesAndOrders(msg, accountWideRiskAction);
      if(!g_riskCloseNoticeShown)
      {
         Alert("TuanProtrade RISK GUARD: Đã gửi yêu cầu đóng lệnh trong phạm vi bảo vệ. Lý do: ", msg);
         g_riskCloseNoticeShown = true;
      }
   }
   else if(!g_riskBreached && !g_manualForceLock)
      g_riskCloseNoticeShown = false;

   // Kiểm soát số lệnh tối đa khi đang trong Chế độ Phục hồi (50% Risk)
   if(g_inRecoveryMode && g_enHalfRiskRec && CountPositionsInScope(InpRiskControlScope == SCOPE_ACCOUNT) > g_maxRecOrders)
   {
      ulong    newestTicket = 0;
      datetime newestTime   = 0;
      string   execSym      = GetExecutionSymbol();
      for(int k = PositionsTotal() - 1; k >= 0; k--)
      {
         ulong tk = PositionGetTicket(k);
         if(tk > 0)
         {
            string s = PositionGetString(POSITION_SYMBOL);
            if(InpRiskControlScope == SCOPE_ACCOUNT || s == _Symbol || s == execSym)
            {
               datetime tOpen = (datetime)PositionGetInteger(POSITION_TIME);
               if(tOpen >= newestTime)
               { newestTime = tOpen; newestTicket = tk; }
            }
         }
      }
      if(newestTicket > 0)
      {
         if(ClosePositionWithConfirmation(newestTicket))
            Alert("CHẾ ĐỘ PHỤC HỒI: Chỉ cho phép mở tối đa ", g_maxRecOrders, " lệnh! Đã đóng lệnh nhồi thêm #", newestTicket);
      }
   }

   // Kiểm tra Lịch tin tức
   datetime newsWinStart = 0, newsWinEnd = 0;
   g_newsLockedState = CheckNewsScheduleAndLock(newsWinStart, newsWinEnd);
   if(g_enNewsFilter && g_newsLockedState)
   {
      string execSym = GetExecutionSymbol();
      for(int j = OrdersTotal() - 1; j >= 0; j--)
      {
         ulong ord = OrderGetTicket(j);
         if(ord > 0)
         {
            string s = OrderGetString(ORDER_SYMBOL);
            if(InpNewsFilterScope == SCOPE_ACCOUNT || s == _Symbol || s == execSym)
               DeleteOrderWithConfirmation(ord);
         }
      }
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t > 0)
         {
            string s = PositionGetString(POSITION_SYMBOL);
            if(InpNewsFilterScope == SCOPE_ACCOUNT || s == _Symbol || s == execSym)
            {
               datetime posOpenTime = (datetime)PositionGetInteger(POSITION_TIME);
               if(newsWinStart > 0 && posOpenTime >= newsWinStart && posOpenTime <= newsWinEnd)
               {
                  if(ClosePositionWithConfirmation(t))
                     Alert("CẤM TRADE TRONG GIỜ TIN! Đã đóng lệnh mở trong khung cấm tin #", t);
               }
            }
         }
      }
   }

   string execSym = GetExecutionSymbol();
   double bid = SymbolInfoDouble(execSym, SYMBOL_BID);
   double ask = SymbolInfoDouble(execSym, SYMBOL_ASK);

   int      buyCount = 0, sellCount = 0;
   double   buyVolSum = 0.0, sellVolSum = 0.0;
   double   buyPriceVolSum = 0.0, sellPriceVolSum = 0.0;
   double   buyPlanVolSum  = 0.0, sellPlanVolSum  = 0.0;
   datetime earliestOpenTime = 0;
   long     anchorPosId      = 0;
   double   repSL = 0.0, repTP = 0.0, netFloatingPnl = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string posSym = PositionGetString(POSITION_SYMBOL);
      if(posSym != _Symbol && posSym != execSym)
         continue;

      double   actualEntry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double   vol          = PositionGetDouble(POSITION_VOLUME);
      double   sl           = SelectedPositionStopForLogic();
      double   tp           = PositionGetDouble(POSITION_TP);
      datetime oTime        = (datetime)PositionGetInteger(POSITION_TIME);
      long     pId          = PositionGetInteger(POSITION_IDENTIFIER);
      double   plannedEntry = GetFrozenClosedEntryPrice(pId, oTime, actualEntry);
      bool     isBuyPos     = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

      netFloatingPnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(earliestOpenTime == 0 || oTime < earliestOpenTime)
      {
         earliestOpenTime = oTime;
         anchorPosId      = pId;
      }
      if(sl > 0.0) repSL = sl;
      if(tp > 0.0) repTP = tp;

      if(isBuyPos)
      {
         buyCount++;
         buyVolSum      += vol;
         buyPriceVolSum += actualEntry  * vol;
         buyPlanVolSum  += plannedEntry * vol;
      }
      else
      {
         sellCount++;
         sellVolSum      += vol;
         sellPriceVolSum += actualEntry  * vol;
         sellPlanVolSum  += plannedEntry * vol;
      }
   }

   int openCount = buyCount + sellCount;
   if(g_prevOpenCountForSetup > 0 && openCount == 0)
   {
      g_hardTpSuppressedForPartial = false;
   }
   g_prevOpenCountForSetup = openCount;

   // Phát hiện vị thế cả Buy và Sell cùng lúc trên Hedging -> Tách riêng quản lý từng lệnh
   g_mixedPositionFallback = (buyVolSum > 1e-8 && sellVolSum > 1e-8);
   if(g_multiMode == MULTI_BASKET_VWAP && g_mixedPositionFallback)
   {
      if(!g_mixedModeWarningShown)
         Alert("ĐANG CÓ CẢ BUY VÀ SELL: EA tự động chuyển sang quản lý từng lệnh độc lập để bảo vệ chính xác từng chiều.");
      g_mixedModeWarningShown = true;
   }
   else
      g_mixedModeWarningShown = false;

   ENUM_MULTI_ORDER_MODE activeMultiMode = (g_multiMode == MULTI_BASKET_VWAP && g_mixedPositionFallback)
                                           ? MULTI_INDIVIDUAL : g_multiMode;
   bool   basketIsLong     = (buyVolSum >= sellVolSum);
   double totalOpenVol     = basketIsLong ? buyVolSum : sellVolSum;
   double vwapEntry        = (totalOpenVol > 0.0) ? ((basketIsLong ? buyPriceVolSum : sellPriceVolSum) / totalOpenVol) : 0.0;
   double plannedVwapEntry = (totalOpenVol > 0.0) ? ((basketIsLong ? buyPlanVolSum  : sellPlanVolSum)  / totalOpenVol) : 0.0;

   if(openCount > 0)
   {
      g_actualFillEntryPrice = vwapEntry;
      g_plannedEntryPrice    = (plannedVwapEntry > 0.0) ? plannedVwapEntry : vwapEntry;
   }
   double currentR = 0.0;

   DrawOrderPinsAndTradingJournal(openCount, vwapEntry, basketIsLong);

   if(openCount > 0 && totalOpenVol > 0.0)
   {
      ENUM_TRADE_SIDE activeSide = basketIsLong ? SIDE_LONG : SIDE_SHORT;
      double curActualSlDist = (repSL > 0.0) ? MathAbs(vwapEntry - repSL) : 0.0;

      g_resolvedAtrTf = ResolveActiveAtrTimeframe(openCount, anchorPosId, earliestOpenTime, curActualSlDist);
      SyncAnchorDateFields(g_resolvedAtrTf, earliestOpenTime);

      bool   trailDataReady = false;
      double rawTrail = ExecuteExactPineScriptFormula(g_resolvedAtrTf, earliestOpenTime, vwapEntry, activeSide,
                                                      g_showAtrPlot && activeMultiMode == MULTI_BASKET_VWAP, false,
                                                      g_pineEntryLevel, g_pineFirstBarSlDist, g_pineStopPlotting,
                                                      g_pineStartCalc, trailDataReady);

      string gvBestTrail        = AccountScopedGV("EAP82_BSK_BESTTRAIL_" + IntegerToString(anchorPosId));
      string gvBestTrailStopped = gvBestTrail + "_STOP";
      if(!trailDataReady)
      {
         bool cachedTrailState = GlobalVariableCheck(gvBestTrailStopped);
         rawTrail           = (cachedTrailState && GlobalVariableCheck(gvBestTrail)) ? GlobalVariableGet(gvBestTrail) : 0.0;
         g_pineStopPlotting = cachedTrailState ? (GlobalVariableGet(gvBestTrailStopped) > 0.5) : true;
         g_pineEntryLevel   = vwapEntry;
         g_pineFirstBarSlDist = curActualSlDist;
      }
      else
         GlobalVariableSet(gvBestTrailStopped, g_pineStopPlotting ? 1.0 : 0.0);

      if(trailDataReady && rawTrail > 0.0 && !g_pineStopPlotting)
      {
         if(GlobalVariableCheck(gvBestTrail))
         {
            double prevBest = GlobalVariableGet(gvBestTrail);
            if(prevBest > 0.0)
               rawTrail = basketIsLong ? MathMax(rawTrail, prevBest) : MathMin(rawTrail, prevBest);
         }
         GlobalVariableSet(gvBestTrail, rawTrail);
      }
      g_pineTrailingStop = rawTrail;

      if(!g_showAtrPlot)
         ObjectsDeleteAll(0, VIS_PREFIX + "ATRLINE_");

      double slDistCalc, slPtsCalc, recLot, dispVol, dispRiskCash, dispRiskPct, dispRewardCash, partLot, remLot;
      bool riskKnown = true;
      CalculateSizingAndActiveRules(openCount, totalOpenVol, vwapEntry, repSL, repTP, basketIsLong, anchorPosId, earliestOpenTime,
                                    slDistCalc, slPtsCalc, recLot, dispVol, dispRiskCash, dispRiskPct, riskKnown, dispRewardCash, partLot, remLot);

      double   prevBarClose = iClose(_Symbol, g_resolvedAtrTf, 1);
      datetime prevBarTime  = iTime(_Symbol,  g_resolvedAtrTf, 1);

      // ======================================================================
      // NHÁNH 1: QUẢN LÝ RỔ LỆNH GỘP THEO GIÁ TRUNG BÌNH VWAP
      // ======================================================================
      if(activeMultiMode == MULTI_BASKET_VWAP)
      {
         string gvBasket1R     = AccountScopedGV("EAP82_BSK_1R_"     + IntegerToString(anchorPosId));
         string gvBasketArmed  = AccountScopedGV("EAP82_BSK_ARMED_"  + IntegerToString(anchorPosId));
         string gvBasketArmBar = AccountScopedGV("EAP82_BSK_ARMBAR_" + IntegerToString(anchorPosId));
         string gvBasketCnt    = AccountScopedGV("EAP82_BSK_CNT_"    + IntegerToString(anchorPosId));
         string gvBasketTier2  = AccountScopedGV("EAP82_BSK_TIER2_"  + IntegerToString(anchorPosId));
         string gvBasketT2Time = AccountScopedGV("EAP82_BSK_T2TIME_" + IntegerToString(anchorPosId));
         string gvLockedInitSL = AccountScopedGV("EAP82_BSK_INITSL_" + IntegerToString(anchorPosId));
         string gvLockedInitTP = AccountScopedGV("EAP82_BSK_INITTP_" + IntegerToString(anchorPosId));

         int    savedCnt = GlobalVariableCheck(gvBasketCnt) ? (int)GlobalVariableGet(gvBasketCnt) : 0;
         double basket1R = GlobalVariableCheck(gvBasket1R)  ? GlobalVariableGet(gvBasket1R)        : 0.0;

         bool isNewOrderAdded   = (openCount > savedCnt);
         bool slStillInRiskZone = (repSL > 0.0) &&
                                  ((basketIsLong && repSL < vwapEntry - _Point) ||
                                   (!basketIsLong && repSL > vwapEntry + _Point));

         if(basket1R <= 0.0 || isNewOrderAdded || (slStillInRiskZone && !g_isTrailingArmedNow))
         {
            basket1R = slStillInRiskZone ? MathAbs(vwapEntry - repSL)
                       : ((slDistCalc > 0.0) ? slDistCalc
                       : ((g_pineFirstBarSlDist > 0.0) ? g_pineFirstBarSlDist : (g_pineLatestAtr * g_customValueForFirstDay)));
            double lockSL = (repSL > 0.0) ? repSL
                            : (basketIsLong ? NormalizeDouble(vwapEntry - basket1R, _Digits) : NormalizeDouble(vwapEntry + basket1R, _Digits));
            double lockTP = (repTP > 0.0) ? repTP
                            : (basketIsLong ? NormalizeDouble(vwapEntry + basket1R * g_targetRR, _Digits) : NormalizeDouble(vwapEntry - basket1R * g_targetRR, _Digits));

            GlobalVariableSet(gvBasket1R,     basket1R);
            GlobalVariableSet(gvLockedInitSL, lockSL);
            GlobalVariableSet(gvLockedInitTP, lockTP);
            GlobalVariableSet(gvBasketCnt,    (double)openCount);
         }
         else if(openCount < savedCnt)
         {
            GlobalVariableSet(gvBasketCnt, (double)openCount);
         }

         double unifiedInitSL = GlobalVariableCheck(gvLockedInitSL) ? GlobalVariableGet(gvLockedInitSL)
                                : (basketIsLong ? NormalizeDouble(vwapEntry - basket1R, _Digits) : NormalizeDouble(vwapEntry + basket1R, _Digits));
         double unifiedInitTP = GlobalVariableCheck(gvLockedInitTP) ? GlobalVariableGet(gvLockedInitTP)
                                : (basketIsLong ? NormalizeDouble(vwapEntry + basket1R * g_targetRR, _Digits) : NormalizeDouble(vwapEntry - basket1R * g_targetRR, _Digits));

         // Kiểm tra trượt giá xấu vượt ngưỡng cho phép sau khi khớp
         double targetRiskBudgetCash = 0.0;
         string targetRiskBudgetReason = "";
         GetRiskCashBudgetForShare(1.0, targetRiskBudgetCash, targetRiskBudgetReason);
         double adverseSlip  = basketIsLong ? (vwapEntry - g_plannedEntryPrice) : (g_plannedEntryPrice - vwapEntry);
         double planned1RRef = (g_standbyLocked1R > 0.0) ? g_standbyLocked1R : basket1R;

         if(InpRejectMaxSlippagePctOf1R > 0.0 && planned1RRef > _Point && adverseSlip > 0.0)
         {
            double slipPct1R = (adverseSlip / planned1RRef) * 100.0;
            if(slipPct1R > InpRejectMaxSlippagePctOf1R)
            {
               CloseAllPositionsOnChartSymbol();
               AlertThrottled("REJECT_SLIP_" + IntegerToString(anchorPosId),
                              StringFormat("TỪ CHỐI LỆNH [%s]: Giá khớp thực tế (%s) trượt xấu %.1f%% 1R so với Entry kế hoạch (%s) > ngưỡng %.1f%%! Đã đóng bảo vệ.",
                                           _Symbol, DoubleToString(vwapEntry, _Digits), slipPct1R, DoubleToString(g_plannedEntryPrice, _Digits), InpRejectMaxSlippagePctOf1R), 30);
               return;
            }
         }

         string gvSlipChecked = AccountScopedGV("EAP85_SLIPCHK_" + IntegerToString(anchorPosId) + "_" + IntegerToString(openCount));
         if(!GlobalVariableCheck(gvSlipChecked))
         {
            bool needRecalcLevels = false;
            if(InpRecalcSlTpOnFillDeviation && MathAbs(vwapEntry - g_plannedEntryPrice) >= _Point)
            {
               double currentSlRef = (repSL > 0.0) ? repSL : unifiedInitSL;
               double actual1RNow  = MathAbs(vwapEntry - currentSlRef);
               if(actual1RNow > _Point)
               {
                  basket1R      = actual1RNow;
                  unifiedInitSL = currentSlRef;
                  unifiedInitTP = basketIsLong ? NormalizeDouble(vwapEntry + basket1R * g_targetRR, _Digits)
                                               : NormalizeDouble(vwapEntry - basket1R * g_targetRR, _Digits);
                  GlobalVariableSet(gvBasket1R,     basket1R);
                  GlobalVariableSet(gvLockedInitSL, unifiedInitSL);
                  GlobalVariableSet(gvLockedInitTP, unifiedInitTP);
                  needRecalcLevels = true;
               }
            }

            if(riskKnown && targetRiskBudgetCash > 0.0 && dispRiskCash > targetRiskBudgetCash * (1.0 + InpMaxRiskOverrunWarnPct / 100.0))
            {
               AlertThrottled("RISK_OVERRUN_" + IntegerToString(anchorPosId),
                              StringFormat("CẢNH BÁO RỦI RO SAU KHỚP [%s]: Khớp %.2f Lot @ %s có Risk thực tế -$%.2f (%.2f%%) vượt ngân sách -$%.2f!",
                                           _Symbol, totalOpenVol, DoubleToString(vwapEntry, _Digits), dispRiskCash, dispRiskPct, targetRiskBudgetCash), 45);

               if(g_volRule == RULE_SCALE_DIST_BY_VOL && !g_isTrailingArmedNow)
               {
                  double safeDist = FindStopDistanceForRiskBudget(execSym, basketIsLong, vwapEntry,
                                                                  targetRiskBudgetCash / totalOpenVol, g_bufferPts, g_commPerLot);
                  if(safeDist > _Point)
                  {
                     basket1R      = safeDist;
                     unifiedInitSL = basketIsLong ? NormalizeDouble(vwapEntry - basket1R, _Digits) : NormalizeDouble(vwapEntry + basket1R, _Digits);
                     unifiedInitTP = basketIsLong ? NormalizeDouble(vwapEntry + basket1R * g_targetRR, _Digits) : NormalizeDouble(vwapEntry - basket1R * g_targetRR, _Digits);
                     GlobalVariableSet(gvBasket1R,     basket1R);
                     GlobalVariableSet(gvLockedInitSL, unifiedInitSL);
                     GlobalVariableSet(gvLockedInitTP, unifiedInitTP);
                     needRecalcLevels = true;
                  }
               }
            }

            if(needRecalcLevels)
            {
               for(int m = PositionsTotal() - 1; m >= 0; m--)
               {
                  ulong tkMod = PositionGetTicket(m);
                  if(tkMod > 0 && (PositionGetString(POSITION_SYMBOL) == _Symbol || PositionGetString(POSITION_SYMBOL) == execSym))
                  {
                     long pidMod = PositionGetInteger(POSITION_IDENTIFIER);
                     GlobalVariableDel(AccountScopedGV("EAP82_INITDONE_" + IntegerToString(pidMod)));
                  }
               }
            }
            GlobalVariableSet(gvSlipChecked, 1.0);
         }

         g_hardTpSuppressedForPartial = false;
         double buffer20Pct1R    = basket1R * (g_tierPctOf1R / 100.0);
         double activeWickBuffer = (g_sweepMode == SWEEP_HARD_SL_ON_LINE) ? 0.0 : buffer20Pct1R;

         double livePrice  = basketIsLong ? bid : ask;
         double profitDist = basketIsLong ? (livePrice - vwapEntry) : (vwapEntry - livePrice);
         currentR = (basket1R > 0.0) ? (profitDist / basket1R) : 0.0;
         datetime curTfBar0 = iTime(_Symbol, g_resolvedAtrTf, 0);

         bool wasArmed = GlobalVariableCheck(gvBasketArmed) ? (GlobalVariableGet(gvBasketArmed) > 0.5) : false;
         datetime armedBarTime = GlobalVariableCheck(gvBasketArmBar) ? (datetime)GlobalVariableGet(gvBasketArmBar) : 0;
         bool justArmedNow = false;

         if(currentR >= g_trailStartRR)
         {
            if(!wasArmed)
            {
               wasArmed     = true;
               justArmedNow = true;
               armedBarTime = curTfBar0;
               GlobalVariableSet(gvBasketArmed,  1.0);
               GlobalVariableSet(gvBasketArmBar, (double)armedBarTime);
            }
         }
         g_isTrailingArmedNow = wasArmed;
         bool allowTrailStepNow = (g_isTrailingArmedNow && !justArmedNow && (armedBarTime == 0 || curTfBar0 > armedBarTime));

         // Ưu tiên P3: Kiểm tra T3 & T2 của ATR Neo trên toàn rổ VWAP
         if(g_enTrail && g_trailStyle == TRAIL_STYLE_AUTO_ATR && allowTrailStepNow && g_pineTrailingStop > 0.0)
         {
            double tier3HardPrice = basketIsLong ? (g_pineTrailingStop - activeWickBuffer)
                                                 : (g_pineTrailingStop + activeWickBuffer);
            if(g_enLock && currentR >= g_lockTrigRR)
            {
               double lockDist = basket1R * g_lockLvlRR;
               double minLockProfitPrc = basketIsLong ? (vwapEntry + lockDist) : (vwapEntry - lockDist);
               tier3HardPrice = basketIsLong ? MathMax(minLockProfitPrc, tier3HardPrice)
                                             : MathMin(minLockProfitPrc, tier3HardPrice);
            }

            // SỬA TRIỆT ĐỂ LỖI SWEEP_WAIT_CANDLE_CLOSE:
            // Chỉ cho phép đóng intrabar khi ở chế độ 3 tầng (SWEEP_3LAYER_20PCT_1R) hoặc SL cứng (SWEEP_HARD_SL_ON_LINE).
            // Chế độ SWEEP_WAIT_CANDLE_CLOSE bắt buộc chờ nến ATR đóng cửa vượt đường ATR!
            bool allowIntrabarT3 = (g_sweepMode == SWEEP_3LAYER_20PCT_1R || g_sweepMode == SWEEP_HARD_SL_ON_LINE);
            bool piercedTier3Realtime = allowIntrabarT3 &&
                                        ((basketIsLong && livePrice <= tier3HardPrice) ||
                                         (!basketIsLong && livePrice >= tier3HardPrice));

            if(piercedTier3Realtime)
            {
               bool allSymbolPositionsClosed = CloseAllPositionsOnChartSymbol();
               if(allSymbolPositionsClosed)
               {
                  string shot = InpAutoScreenshotOnTrade ? CaptureChartScreenshot(true, "T3_BREAK") : "";
                  AlertThrottled("T3_SL_DONE", StringFormat("T3 (SL 100%%): Giá xuyên thủng biên bảo vệ 3 tầng -> đã đóng toàn bộ vị thế trên %s.", _Symbol));
                  if(InpTelegramOnClose)
                     QueueTradeDeskNotification("TradeDesk T3 FULL EXIT | " + _Symbol, true, shot);
               }
               return;
            }

            if(prevBarTime > earliestOpenTime && (armedBarTime == 0 || prevBarTime > armedBarTime))
            {
               bool closedBeyondTier1 = (basketIsLong && prevBarClose < g_pineTrailingStop) ||
                                        (!basketIsLong && prevBarClose > g_pineTrailingStop);
               bool closedBeyondTier3 = (basketIsLong && prevBarClose <= tier3HardPrice) ||
                                        (!basketIsLong && prevBarClose >= tier3HardPrice);

               if(g_sweepMode == SWEEP_3LAYER_20PCT_1R)
               {
                  bool alreadyCutTier2 = GlobalVariableCheck(gvBasketTier2);
                  datetime lastT2Bar   = GlobalVariableCheck(gvBasketT2Time) ? (datetime)GlobalVariableGet(gvBasketT2Time) : 0;

                  if(closedBeyondTier3)
                  {
                     if(CloseAllPositionsOnChartSymbol())
                        AlertThrottled("T3_CLOSE_DONE", "T3: Nến đóng cửa xuyên thủng biên 20% của 1R -> đã đóng hết vị thế.");
                     return;
                  }
                  else if(closedBeyondTier1)
                  {
                     if(!alreadyCutTier2)
                     {
                        bool allTier2Done = true;
                        bool foundTier2Position = false;
                        for(int c = PositionsTotal() - 1; c >= 0; c--)
                        {
                           ulong tk = PositionGetTicket(c);
                           if(tk == 0) continue;
                           string s = PositionGetString(POSITION_SYMBOL);
                           if(s != _Symbol && s != execSym) continue;
                           foundTier2Position = true;
                           long tier2PosId = PositionGetInteger(POSITION_IDENTIFIER);
                           string gvPosDone = AccountScopedGV("EAP82_BSK_T2POS_" + IntegerToString(tier2PosId));
                           if(GlobalVariableCheck(gvPosDone))
                              continue;
                           double vol = PositionGetDouble(POSITION_VOLUME);
                           double halfVol = FloorLotStep(vol * 0.5);
                           double closedHalf = 0.0;
                           if(halfVol >= SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN) &&
                              ClosePositionPartiallyByTicket(tk, halfVol, closedHalf))
                           {
                              GlobalVariableSet(gvPosDone, 1.0);
                           }
                           else
                              allTier2Done = false;
                        }
                        if(allTier2Done && foundTier2Position)
                        {
                           GlobalVariableSet(gvBasketTier2,  prevBarClose);
                           GlobalVariableSet(gvBasketT2Time, (double)prevBarTime);
                           string shot = InpAutoScreenshotOnTrade ? CaptureChartScreenshot(true, "T2_CUT50") : "";
                           Alert(StringFormat("T2: Nến %s đóng cửa vượt T1 nhưng giữ được biên %.0f%% 1R -> đã cắt 50%% vị thế.",
                                              GetTfShortName(g_resolvedAtrTf), g_tierPctOf1R));
                           if(InpTelegramOnClose)
                              QueueTradeDeskNotification("TradeDesk T2 50% CUT | " + _Symbol, true, shot);
                        }
                     }

                     if(GlobalVariableCheck(gvBasketTier2) && prevBarTime > lastT2Bar)
                     {
                        double t2RefClose = GlobalVariableGet(gvBasketTier2);
                        bool droppedFurther = (basketIsLong && prevBarClose < t2RefClose) ||
                                              (!basketIsLong && prevBarClose > t2RefClose);
                        if(droppedFurther)
                        {
                           if(CloseAllPositionsOnChartSymbol())
                              AlertThrottled("T3_AFTER_T2_DONE", "T3: Giá tiếp tục giảm sau T2 -> đã đóng hết vị thế còn lại.");
                           return;
                        }
                     }
                  }
               }
               else if(g_sweepMode == SWEEP_WAIT_CANDLE_CLOSE && closedBeyondTier1)
               {
                  if(CloseAllPositionsOnChartSymbol())
                     AlertThrottled("ATR_WICK_DONE", "ATR WICK-PROOF (CHỜ NẾN ĐÓNG): Nến đã đóng cửa vượt đường ATR -> đã đóng hết vị thế.");
                  return;
               }
            }
         }

         // Điều phối P4 (Ma trận 10 TP / 10 SL), P5 (BE 4 cấp / Common BE / Lock), P6 (9 Trailing), P7 (Init SL/TP) cho từng vị thế trong rổ qua Trọng tài
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            string s = PositionGetString(POSITION_SYMBOL);
            if(s != _Symbol && s != execSym) continue;
            bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
            if(isLong != basketIsLong)
               continue;

            long   posId  = PositionGetInteger(POSITION_IDENTIFIER);
            double curSL  = SelectedPositionStopForLogic();
            double curTP  = PositionGetDouble(POSITION_TP);
            double curVol = PositionGetDouble(POSITION_VOLUME);
            string gvPart     = AccountScopedGV("EAP82_PART_"     + IntegerToString(posId));
            string gvInitDone = AccountScopedGV("EAP82_INITDONE_" + IntegerToString(posId));
            bool   partialHistoryReady = PreparePositionPartialState(posId, gvPart);
            bool   partAlreadyDone     = (GlobalVariableCheck(gvPart) || GetPositionBitmask(PartialTpMaskKey(posId)) != 0);

            SArbiterDecision dec;
            ZeroMemory(dec);
            dec.ticket     = ticket;
            dec.positionId = posId;
            dec.isBuy      = isLong;

            // P7: Gắn SL/TP khởi tạo & kiểm tra gỡ Hard TP xung đột
            double candidateTP = (curTP > 0.0 && !isNewOrderAdded) ? curTP : unifiedInitTP;
            bool removeHardTpAtPartial = ShouldSuppressBrokerHardTpForPartial(curVol, partAlreadyDone, vwapEntry,
                                                                              (curSL > 0.0 ? curSL : unifiedInitSL), candidateTP, isLong);
            if(removeHardTpAtPartial)
            {
               g_hardTpSuppressedForPartial = true;
               dec.suppressHardTp           = true;
            }

            if(g_autoSlTp && (!GlobalVariableCheck(gvInitDone) || isNewOrderAdded))
            {
               dec.attachInitLevels = true;
               dec.candidateSL      = (curSL <= 0.0 || isNewOrderAdded) ? unifiedInitSL : curSL;
               dec.candidateTP      = removeHardTpAtPartial ? 0.0
                                      : ((curTP <= 0.0 || isNewOrderAdded || InpRecalcSlTpOnFillDeviation) ? unifiedInitTP : curTP);
               GlobalVariableSet(gvInitDone, 1.0);
            }

            // P4: Thực thi Ma trận 10 Cấp Partial TP & 10 Cấp Partial SL
            if(partialHistoryReady)
            {
               double closedTpVol = 0.0, closedSlVol = 0.0;
               ProcessPartialTpMatrix(ticket, posId, isLong, vwapEntry, basket1R, currentR, curVol, closedTpVol);
               if(closedTpVol > 0.0)
               {
                  GlobalVariableSet(gvPart, 1.0);
                  curVol = MathMax(0.0, curVol - closedTpVol);
               }
               if(curVol >= SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN))
               {
                  ProcessPartialSlMatrix(ticket, posId, isLong, vwapEntry, basket1R, currentR, curVol, closedSlVol);
                  curVol = MathMax(0.0, curVol - closedSlVol);
               }
            }
            if(!PositionSelectByTicket(ticket))
               continue;

            // P5: Thu thập đề xuất SL từ Breakeven cơ bản, Common BE, Lock Profit & Breakeven 4 cấp
            string beSrc = "";
            double beLockCand = ComputePositionBeAndLockCandidate(posId, isLong, PositionGetDouble(POSITION_PRICE_OPEN),
                                                                  vwapEntry, basket1R, currentR, curTP, curSL, beSrc);

            // P6: Thu thập đề xuất SL từ kiểu Trailing đang chọn (ATR Neo chủ lực HOẶC 1 trong 8 kiểu mở rộng)
            double trailCand = curSL;
            string trailSrc  = "";
            if(!justArmedNow && g_trailStyle != TRAIL_STYLE_MANUAL_SL)
            {
               if(g_advTrailMode == ADV_TRAIL_OFF)
               {
                  if(g_enTrail && g_trailStyle == TRAIL_STYLE_AUTO_ATR && allowTrailStepNow && g_pineTrailingStop > 0.0)
                  {
                     trailCand = isLong ? NormalizeDouble(g_pineTrailingStop - activeWickBuffer, _Digits)
                                        : NormalizeDouble(g_pineTrailingStop + activeWickBuffer, _Digits);
                     trailSrc  = "ATR_ANCHORED";
                  }
               }
               else
               {
                  double stepPartVol = 0.0;
                  trailCand = ComputeAdvancedTrailCandidateForPosition(ticket, posId, isLong, vwapEntry, basket1R,
                                                                       currentR, curSL, curVol, stepPartVol, trailSrc);
                  if(stepPartVol > 0.0)
                     dec.partialCloseVol += stepPartVol;
               }
            }

            // Chọn giá SL tốt nhất giữa P5 (BE/Lock), P6 (Trailing) và P7 (Init)
            double bestCand = dec.candidateSL;
            if(isLong)
            {
               if(beLockCand > bestCand) { bestCand = beLockCand; dec.slWinnerSource = beSrc; }
               if(trailCand  > bestCand) { bestCand = trailCand;  dec.slWinnerSource = trailSrc; }
            }
            else
            {
               if(beLockCand > 0.0 && (bestCand <= 0.0 || beLockCand < bestCand)) { bestCand = beLockCand; dec.slWinnerSource = beSrc; }
               if(trailCand  > 0.0 && (bestCand <= 0.0 || trailCand  < bestCand)) { bestCand = trailCand;  dec.slWinnerSource = trailSrc; }
            }
            dec.candidateSL = bestCand;

            // Ủy quyền cho Trọng tài thực thi duy nhất 1 lần
            ExecuteArbiterDecision(dec);
            if(PositionSelectByTicket(ticket))
            {
               repSL = SelectedPositionStopForLogic();
               repTP = PositionGetDouble(POSITION_TP);
            }
         }

         DrawCurrentAtrSpotlight(g_pineTrailingStop, basket1R, activeSide, openCount, repSL, g_pineStopPlotting, currentR, g_isTrailingArmedNow);
      }
      // ======================================================================
      // NHÁNH 2: QUẢN LÝ TÁCH BIỆT TỪNG LỆNH ĐỘC LẬP (MULTI_INDIVIDUAL)
      // ======================================================================
      else
      {
         g_isTrailingArmedNow = false;
         ObjectsDeleteAll(0, VIS_PREFIX + "ATRLINE_");
         DrawCurrentAtrSpotlight(0.0, 0.0, basketIsLong ? SIDE_LONG : SIDE_SHORT, openCount, repSL, false, currentR, false);
         double individualRiskWeightedR = 0.0;
         double individualRiskWeight    = 0.0;

         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;
            string s = PositionGetString(POSITION_SYMBOL);
            if(s != _Symbol && s != execSym) continue;

            long     posId       = PositionGetInteger(POSITION_IDENTIFIER);
            datetime openTime    = (datetime)PositionGetInteger(POSITION_TIME);
            double   actualEntry = PositionGetDouble(POSITION_PRICE_OPEN);
            double   curSL       = SelectedPositionStopForLogic();
            double   curTP       = PositionGetDouble(POSITION_TP);
            double   curVol      = PositionGetDouble(POSITION_VOLUME);
            bool     isLong      = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
            double   livePrice   = isLong ? bid : ask;

            ENUM_TIMEFRAMES indTf = ResolveActiveAtrTimeframe(1, posId, openTime, (curSL > 0.0 ? MathAbs(actualEntry - curSL) : 0.0));
            double plannedEntry   = GetFrozenClosedEntryPrice(posId, openTime, actualEntry);
            double entry          = actualEntry;

            double indEntry = 0.0, indFirstDist = 0.0;
            bool   indStopPlot = false, indStart = false, indDataReady = false;
            double indTrail = ExecuteExactPineScriptFormula(indTf, openTime, entry, isLong ? SIDE_LONG : SIDE_SHORT,
                                                            false, false, indEntry, indFirstDist, indStopPlot, indStart, indDataReady);

            string gvBestInd        = AccountScopedGV("EAP82_IND_BEST_" + IntegerToString(posId));
            string gvBestIndStopped = gvBestInd + "_STOP";
            if(!indDataReady)
            {
               bool cachedIndTrailState = GlobalVariableCheck(gvBestIndStopped);
               indTrail     = (cachedIndTrailState && GlobalVariableCheck(gvBestInd)) ? GlobalVariableGet(gvBestInd) : 0.0;
               indStopPlot  = cachedIndTrailState ? (GlobalVariableGet(gvBestIndStopped) > 0.5) : true;
               indEntry     = entry;
               indFirstDist = (curSL > 0.0) ? MathAbs(entry - curSL) : 0.0;
            }
            else
               GlobalVariableSet(gvBestIndStopped, indStopPlot ? 1.0 : 0.0);

            if(indDataReady && indTrail > 0.0 && !indStopPlot)
            {
               if(GlobalVariableCheck(gvBestInd))
               {
                  double prevB = GlobalVariableGet(gvBestInd);
                  if(prevB > 0.0)
                     indTrail = isLong ? MathMax(indTrail, prevB) : MathMin(indTrail, prevB);
               }
               GlobalVariableSet(gvBestInd, indTrail);
            }

            string gv1R       = AccountScopedGV("EAP82_1R_"       + IntegerToString(posId));
            string gvPart     = AccountScopedGV("EAP82_PART_"     + IntegerToString(posId));
            bool   partialHistoryReady = PreparePositionPartialState(posId, gvPart);
            string gvArmed    = AccountScopedGV("EAP82_ARMED_"    + IntegerToString(posId));
            string gvArmBar   = AccountScopedGV("EAP82_ARMBAR_"   + IntegerToString(posId));
            string gvInitDone = AccountScopedGV("EAP82_INITDONE_" + IntegerToString(posId));
            string gvTier2    = AccountScopedGV("EAP82_TIER2_"    + IntegerToString(posId));
            string gvT2Time   = AccountScopedGV("EAP82_T2TIME_"   + IntegerToString(posId));
            double slDist     = GlobalVariableCheck(gv1R) ? GlobalVariableGet(gv1R) : 0.0;

            bool indSlInRisk = (curSL > 0.0) &&
                               ((isLong && curSL < entry - _Point) || (!isLong && curSL > entry + _Point));
            if(slDist <= 0.0 || indSlInRisk)
            {
               slDist = indSlInRisk ? MathAbs(entry - curSL) : ((indFirstDist > 0.0) ? indFirstDist : slDistCalc);
               GlobalVariableSet(gv1R, slDist);
            }

            double indAdverseSlip = isLong ? (actualEntry - plannedEntry) : (plannedEntry - actualEntry);
            if(InpRejectMaxSlippagePctOf1R > 0.0 && slDist > _Point && indAdverseSlip > 0.0)
            {
               double indSlipPct = (indAdverseSlip / slDist) * 100.0;
               if(indSlipPct > InpRejectMaxSlippagePctOf1R)
               {
                  ClosePositionWithConfirmation(ticket);
                  AlertThrottled("IND_REJECT_SLIP_" + IntegerToString(posId),
                                 StringFormat("TỪ CHỐI LỆNH #%I64u: Giá khớp (%s) trượt xấu %.1f%% 1R so với Entry kế hoạch (%s)! Đã đóng lệnh.",
                                              ticket, DoubleToString(actualEntry, _Digits), indSlipPct, DoubleToString(plannedEntry, _Digits)), 30);
                  continue;
               }
            }

            double initSL = (curSL > 0.0) ? curSL : (isLong ? NormalizeDouble(entry - slDist, _Digits) : NormalizeDouble(entry + slDist, _Digits));
            double rawTP  = (curTP > 0.0 && !InpRecalcSlTpOnFillDeviation) ? curTP
                            : (isLong ? NormalizeDouble(entry + slDist * g_targetRR, _Digits) : NormalizeDouble(entry - slDist * g_targetRR, _Digits));
            bool partAlreadyDone = (GlobalVariableCheck(gvPart) || GetPositionBitmask(PartialTpMaskKey(posId)) != 0);
            bool useIndTrailNoHardTp = ShouldSuppressBrokerHardTpForPartial(curVol, partAlreadyDone, entry, initSL, rawTP, isLong);
            if(useIndTrailNoHardTp)
               g_hardTpSuppressedForPartial = true;

            double indBuf20Pct1R = slDist * (g_tierPctOf1R / 100.0);
            double indWickBuffer = (g_sweepMode == SWEEP_HARD_SL_ON_LINE) ? 0.0 : indBuf20Pct1R;

            double profDist = isLong ? (livePrice - entry) : (entry - livePrice);
            double ticketR  = (slDist > 0.0) ? (profDist / slDist) : 0.0;
            double initialStopForR = isLong ? (actualEntry - slDist) : (actualEntry + slDist);
            double ticketInitialRiskCash = 0.0;
            if(slDist > 0.0 && EstimateStopRiskCash(execSym, isLong, curVol, actualEntry,
                                                    initialStopForR, g_bufferPts, g_commPerLot, ticketInitialRiskCash) && ticketInitialRiskCash > 0.0)
            {
               individualRiskWeightedR += ticketR * ticketInitialRiskCash;
               individualRiskWeight    += ticketInitialRiskCash;
            }
            datetime indCurBar0 = iTime(_Symbol, indTf, 0);

            bool ticketArmed = GlobalVariableCheck(gvArmed) ? (GlobalVariableGet(gvArmed) > 0.5) : false;
            datetime indArmedBar = GlobalVariableCheck(gvArmBar) ? (datetime)GlobalVariableGet(gvArmBar) : 0;
            bool indJustArmed = false;

            if(ticketR >= g_trailStartRR && !ticketArmed)
            {
               ticketArmed  = true;
               indJustArmed = true;
               indArmedBar  = indCurBar0;
               GlobalVariableSet(gvArmed,  1.0);
               GlobalVariableSet(gvArmBar, (double)indArmedBar);
            }
            if(ticketArmed)
               g_isTrailingArmedNow = true;

            bool indAllowTrailNow = (ticketArmed && !indJustArmed && (indArmedBar == 0 || indCurBar0 > indArmedBar));
            double   indPrevClose = iClose(_Symbol, indTf, 1);
            datetime indPrevTime  = iTime(_Symbol,  indTf, 1);

            // Kiểm tra T3 & T2 cho từng vị thế riêng lẻ
            if(g_enTrail && g_trailStyle == TRAIL_STYLE_AUTO_ATR && indAllowTrailNow && indTrail > 0.0)
            {
               double t3HardP = isLong ? (indTrail - indWickBuffer) : (indTrail + indWickBuffer);
               if(g_enLock && ticketR >= g_lockTrigRR)
               {
                  double lockD     = slDist * g_lockLvlRR;
                  double minFloorL = isLong ? (entry + lockD) : (entry - lockD);
                  t3HardP = isLong ? MathMax(minFloorL, t3HardP) : MathMin(minFloorL, t3HardP);
               }

               bool allowIntrabarT3 = (g_sweepMode == SWEEP_3LAYER_20PCT_1R || g_sweepMode == SWEEP_HARD_SL_ON_LINE);
               if(allowIntrabarT3 && ((isLong && livePrice <= t3HardP) || (!isLong && livePrice >= t3HardP)))
               {
                  ClosePositionWithConfirmation(ticket);
                  continue;
               }

               if(indPrevTime > openTime && (indArmedBar == 0 || indPrevTime > indArmedBar))
               {
                  bool cBeyondT1 = (isLong && indPrevClose < indTrail) || (!isLong && indPrevClose > indTrail);
                  bool cBeyondT3 = (isLong && indPrevClose <= t3HardP) || (!isLong && indPrevClose >= t3HardP);

                  if(g_sweepMode == SWEEP_3LAYER_20PCT_1R)
                  {
                     bool hasT2   = GlobalVariableCheck(gvTier2);
                     datetime t2T = GlobalVariableCheck(gvT2Time) ? (datetime)GlobalVariableGet(gvT2Time) : 0;

                     if(cBeyondT3)
                     {
                        ClosePositionWithConfirmation(ticket);
                        continue;
                     }
                     else if(cBeyondT1)
                     {
                        if(!hasT2)
                        {
                           double halfVol = FloorLotStep(curVol * 0.5);
                           double actualClosed = 0.0;
                           if(halfVol >= SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN) &&
                              ClosePositionPartiallyByTicket(ticket, halfVol, actualClosed))
                           {
                              GlobalVariableSet(gvTier2,  indPrevClose);
                              GlobalVariableSet(gvT2Time, (double)indPrevTime);
                              GlobalVariableSet(gvPart,   1.0);
                              curVol = MathMax(0.0, curVol - actualClosed);
                           }
                        }
                        else if(indPrevTime > t2T)
                        {
                           double prevT2Close = GlobalVariableGet(gvTier2);
                           if((isLong && indPrevClose < prevT2Close) || (!isLong && indPrevClose > prevT2Close))
                           {
                              ClosePositionWithConfirmation(ticket);
                              continue;
                           }
                        }
                     }
                  }
                  else if(g_sweepMode == SWEEP_WAIT_CANDLE_CLOSE && cBeyondT1)
                  {
                     ClosePositionWithConfirmation(ticket);
                     continue;
                  }
               }
            }

            // Thực thi Ma trận 10 TP / 10 SL, BE 4 cấp, 9 Trailing qua Trọng tài cho từng lệnh
            SArbiterDecision dec;
            ZeroMemory(dec);
            dec.ticket         = ticket;
            dec.positionId     = posId;
            dec.isBuy          = isLong;
            dec.suppressHardTp = useIndTrailNoHardTp;

            if(g_autoSlTp && !GlobalVariableCheck(gvInitDone))
            {
               dec.attachInitLevels = true;
               dec.candidateSL      = initSL;
               dec.candidateTP      = useIndTrailNoHardTp ? 0.0 : rawTP;
               GlobalVariableSet(gvInitDone, 1.0);
            }

            if(partialHistoryReady)
            {
               double closedTpVol = 0.0, closedSlVol = 0.0;
               ProcessPartialTpMatrix(ticket, posId, isLong, entry, slDist, ticketR, curVol, closedTpVol);
               if(closedTpVol > 0.0)
               {
                  GlobalVariableSet(gvPart, 1.0);
                  curVol = MathMax(0.0, curVol - closedTpVol);
               }
               if(curVol >= SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN))
               {
                  ProcessPartialSlMatrix(ticket, posId, isLong, entry, slDist, ticketR, curVol, closedSlVol);
                  curVol = MathMax(0.0, curVol - closedSlVol);
               }
            }
            if(!PositionSelectByTicket(ticket))
               continue;

            string beSrc = "";
            double beLockCand = ComputePositionBeAndLockCandidate(posId, isLong, entry, entry, slDist, ticketR, curTP, curSL, beSrc);
            double trailCand  = curSL;
            string trailSrc   = "";
            if(!indJustArmed && g_trailStyle != TRAIL_STYLE_MANUAL_SL)
            {
               if(g_advTrailMode == ADV_TRAIL_OFF)
               {
                  if(g_enTrail && g_trailStyle == TRAIL_STYLE_AUTO_ATR && indAllowTrailNow && indTrail > 0.0)
                  {
                     trailCand = isLong ? NormalizeDouble(indTrail - indWickBuffer, _Digits)
                                        : NormalizeDouble(indTrail + indWickBuffer, _Digits);
                     trailSrc  = "ATR_ANCHORED";
                  }
               }
               else
               {
                  double stepPartVol = 0.0;
                  trailCand = ComputeAdvancedTrailCandidateForPosition(ticket, posId, isLong, entry, slDist,
                                                                       ticketR, curSL, curVol, stepPartVol, trailSrc);
                  if(stepPartVol > 0.0)
                     dec.partialCloseVol += stepPartVol;
               }
            }

            double bestCand = dec.candidateSL;
            if(isLong)
            {
               if(beLockCand > bestCand) { bestCand = beLockCand; dec.slWinnerSource = beSrc; }
               if(trailCand  > bestCand) { bestCand = trailCand;  dec.slWinnerSource = trailSrc; }
            }
            else
            {
               if(beLockCand > 0.0 && (bestCand <= 0.0 || beLockCand < bestCand)) { bestCand = beLockCand; dec.slWinnerSource = beSrc; }
               if(trailCand  > 0.0 && (bestCand <= 0.0 || trailCand  < bestCand)) { bestCand = trailCand;  dec.slWinnerSource = trailSrc; }
            }
            dec.candidateSL = bestCand;

            ExecuteArbiterDecision(dec);
         }

         currentR = (individualRiskWeight > 0.0) ? (individualRiskWeightedR / individualRiskWeight) : 0.0;
      }
   }
   else // KHI CHỜ LỆNH (STANDBY MODE)
   {
      g_isTrailingArmedNow         = false;
      g_hardTpSuppressedForPartial = false;
      g_resolvedAtrTf              = ResolveActiveAtrTimeframe(0, 0, 0, 0.0);
      SyncAnchorDateFields(g_resolvedAtrTf, 0);

      datetime standbyAnchorTime = 0;
      if(InpLockStandbySetupTfAndBar && g_standbySetupLocked && g_standbyLockedAnchorTime > 0)
      {
         standbyAnchorTime = g_standbyLockedAnchorTime;
      }
      else if(g_autoSyncDate)
      {
         datetime tfLookbackTime = iTime(_Symbol, g_resolvedAtrTf, g_standbyLookback);
         standbyAnchorTime = (tfLookbackTime > 0) ? tfLookbackTime : (TimeCurrent() - PeriodSeconds(g_resolvedAtrTf) * g_standbyLookback);
         if(InpLockStandbySetupTfAndBar && standbyAnchorTime > 0)
            g_standbyLockedAnchorTime = standbyAnchorTime;
      }
      else
      {
         standbyAnchorTime = StringToTime(StringFormat("%04d.%02d.%02d 00:00", g_entryDateYear, g_entryDateMonth, g_entryDateDay));
         if(InpLockStandbySetupTfAndBar && standbyAnchorTime > 0)
            g_standbyLockedAnchorTime = standbyAnchorTime;
      }

      bool   standbyDataReady = false;
      double standbyEntryRef  = (InpLockStandbySetupTfAndBar && g_standbySetupLocked && g_standbyLockedEntry > 0.0)
                                ? g_standbyLockedEntry : g_entryPriceInput;
      g_pineTrailingStop = ExecuteExactPineScriptFormula(g_resolvedAtrTf, standbyAnchorTime, standbyEntryRef, g_tradeSide,
                                                         g_showAtrPlot, g_autoRestartAtr,
                                                         g_pineEntryLevel, g_pineFirstBarSlDist, g_pineStopPlotting,
                                                         g_pineStartCalc, standbyDataReady);
      if(!standbyDataReady)
         g_pineTrailingStop = 0.0;
      if(!g_showAtrPlot)
         ObjectsDeleteAll(0, VIS_PREFIX + "ATRLINE_");

      DrawCurrentAtrSpotlight(g_pineTrailingStop, g_pineFirstBarSlDist, g_tradeSide, 0, 0.0, g_pineStopPlotting, 0.0, false);
   }

   UpdateHudAndTabValues(dayPct, weekPct, monthPct, openCount, totalOpenVol, vwapEntry,
                         repSL, repTP, basketIsLong, anchorPosId, earliestOpenTime, currentR, netFloatingPnl);
}
// ============================================================================
// MODULE 11: CUiDiffRenderer (GIAO DIỆN KHUNG KÉP, NGĂN KÉO MA TRẬN & HOTKEYS)
// ============================================================================

//+------------------------------------------------------------------+
//| Kẹp tọa độ Bảng điều khiển luôn nằm gọn trong khung biểu đồ      |
//+------------------------------------------------------------------+
void ClampPanelCoordinates()
{
   long chartW = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   long chartH = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   int totalW = g_panelW + ((g_drawerMode != DRAWER_CLOSED && !g_isMinimized) ? (g_drawerW + 6) : 0);
   int maxX   = MathMax(5, (int)chartW - totalW - 6);
   int maxY   = MathMax(5, (int)chartH - g_headerH - 8);

   if(g_panelX < 5)    g_panelX = 5;
   if(g_panelX > maxX) g_panelX = maxX;
   if(g_panelY < 5)    g_panelY = 5;
   if(g_panelY > maxY) g_panelY = maxY;
}

//+------------------------------------------------------------------+
//| Các hàm tạo & cập nhật đối tượng UI theo cơ chế Vi sai (Diff UI) |
//+------------------------------------------------------------------+
void CreateBox(string name, int x, int y, int w, int h, color bg, color border)
{
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   }
   if(ObjectGetInteger(0, obj, OBJPROP_XDISTANCE) != x) ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   if(ObjectGetInteger(0, obj, OBJPROP_YDISTANCE) != y) ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   if(ObjectGetInteger(0, obj, OBJPROP_XSIZE)     != w) ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   if(ObjectGetInteger(0, obj, OBJPROP_YSIZE)     != h) ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   if((color)ObjectGetInteger(0, obj, OBJPROP_BGCOLOR) != bg)     ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   if((color)ObjectGetInteger(0, obj, OBJPROP_COLOR)   != border) ObjectSetInteger(0, obj, OBJPROP_COLOR, border);
}

void CreateTxt(string name, int x, int y, string text, color clr, bool bold, int customSize = 0)
{
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   }
   int fSize = (customSize > 0) ? customSize : InpFontSize;
   string fName = bold ? "Segoe UI Bold" : "Segoe UI";
   if(ObjectGetInteger(0, obj, OBJPROP_XDISTANCE) != x)        ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   if(ObjectGetInteger(0, obj, OBJPROP_YDISTANCE) != y)        ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   if(ObjectGetString(0, obj, OBJPROP_FONT)       != fName)    ObjectSetString(0, obj, OBJPROP_FONT, fName);
   if(ObjectGetInteger(0, obj, OBJPROP_FONTSIZE)  != fSize)    ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, fSize);
   if((color)ObjectGetInteger(0, obj, OBJPROP_COLOR) != clr)   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   if(ObjectGetString(0, obj, OBJPROP_TEXT)       != text)     ObjectSetString(0, obj, OBJPROP_TEXT, text);
}

void CreateEditBox(string name, int x, int y, int w, int h, string initVal, bool readOnly = false, string tooltip = "")
{
   string obj = PREFIX + name;
   bool isNew = false;
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_EDIT, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_ALIGN, ALIGN_CENTER);
      ObjectSetString(0, obj, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetString(0, obj, OBJPROP_TEXT, initVal);
      isNew = true;
   }
   ObjectSetInteger(0, obj, OBJPROP_READONLY, readOnly);
   if(ObjectGetInteger(0, obj, OBJPROP_XDISTANCE) != x) ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   if(ObjectGetInteger(0, obj, OBJPROP_YDISTANCE) != y) ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   if(ObjectGetInteger(0, obj, OBJPROP_XSIZE)     != w) ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   if(ObjectGetInteger(0, obj, OBJPROP_YSIZE)     != h) ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, readOnly ? C_EDIT_MUTED : C_EDIT_BG);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, C_EDIT_TXT);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, C_BORDER);
   if(!isNew && (!g_isEditingTextField || g_focusedEditName != obj))
   {
      if(ObjectGetString(0, obj, OBJPROP_TEXT) != initVal)
         ObjectSetString(0, obj, OBJPROP_TEXT, initVal);
   }
   if(tooltip != "")
      ObjectSetString(0, obj, OBJPROP_TOOLTIP, tooltip);
}

void CreateBtn(string name, int x, int y, int w, int h, string text, color bg, color txtClr, string tooltip = "")
{
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, obj, OBJPROP_FONT, "Segoe UI Bold");
   }
   if(ObjectGetInteger(0, obj, OBJPROP_XDISTANCE) != x)      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   if(ObjectGetInteger(0, obj, OBJPROP_YDISTANCE) != y)      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   if(ObjectGetInteger(0, obj, OBJPROP_XSIZE)     != w)      ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   if(ObjectGetInteger(0, obj, OBJPROP_YSIZE)     != h)      ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   if(ObjectGetInteger(0, obj, OBJPROP_FONTSIZE)  != InpFontSize) ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, InpFontSize);
   if((color)ObjectGetInteger(0, obj, OBJPROP_BGCOLOR) != bg)     ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   if((color)ObjectGetInteger(0, obj, OBJPROP_COLOR)   != txtClr) ObjectSetInteger(0, obj, OBJPROP_COLOR, txtClr);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, C_BORDER);
   ObjectSetInteger(0, obj, OBJPROP_STATE, false);
   if(ObjectGetString(0, obj, OBJPROP_TEXT) != text)
      ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetString(0, obj, OBJPROP_TOOLTIP, (tooltip != "") ? tooltip : text);
}

//+------------------------------------------------------------------+
//| Các hàm lấy nhãn hiển thị gọn không cắt chữ cho các nút chọn     |
//+------------------------------------------------------------------+
string GetAtrTfBtnLabel()
{
   string activeTf = GetTfShortName(g_resolvedAtrTf);
   switch(g_atrTfMode)
   {
      case ATR_TF_AUTO_ENTRY: return "TF: AUTO (" + activeTf + ")";
      case ATR_TF_FIXED_H1:   return "TF: CỐ ĐỊNH H1";
      case ATR_TF_FIXED_M15:  return "TF: CỐ ĐỊNH M15";
      case ATR_TF_FIXED_M5:   return "TF: CỐ ĐỊNH M5";
      case ATR_TF_FIXED_H4:   return "TF: CỐ ĐỊNH H4";
      case ATR_TF_FIXED_D1:   return "TF: CỐ ĐỊNH D1";
      default:                return "TF: CHART (" + activeTf + ")";
   }
}

string GetEntryModeBtnLabel()
{
   switch(g_entryMode)
   {
      case ENTRY_MODE_MARKET:     return "KIỂU: MARKET ▾";
      case ENTRY_MODE_LIMIT:      return "KIỂU: LIMIT ▾";
      case ENTRY_MODE_STOP:       return "KIỂU: STOP ▾";
      case ENTRY_MODE_LPO:        return "KIỂU: LPO 2 PHA ▾";
      case ENTRY_MODE_STOP_LIMIT: return "KIỂU: STOP-LIMIT ▾";
      case ENTRY_MODE_OCO:        return "KIỂU: CẶP OCO ▾";
   }
   return "KIỂU: MARKET ▾";
}

string GetOcoModeBtnLabel()
{
   switch(g_ocoMode)
   {
      case OCO_BREAKOUT_STOP_STOP:   return "OCO: STOP-STOP";
      case OCO_REVERSAL_LIMIT_LIMIT: return "OCO: LIMIT-LIMIT";
      case OCO_DIRECTIONAL_BUY:      return "OCO: BUY LIM+STP";
      case OCO_DIRECTIONAL_SELL:     return "OCO: SELL LIM+STP";
      case OCO_CUSTOM_ADOPT:         return "OCO: GOM LỆNH CHỜ";
   }
   return "OCO: STOP-STOP";
}

string GetAdvTrailBtnLabel()
{
   switch(g_advTrailMode)
   {
      case ADV_TRAIL_OFF:          return "ATR NEO (CHỦ LỰC)";
      case ADV_TRAIL_MA:           return "TRAIL: ĐƯỜNG MA";
      case ADV_TRAIL_FRACTAL:      return "TRAIL: FRACTALS";
      case ADV_TRAIL_PSAR:         return "TRAIL: PARABOLIC SAR";
      case ADV_TRAIL_PIPS_BASIC:   return "TRAIL: PIPS CƠ BẢN";
      case ADV_TRAIL_MULTI_4STAGE: return "TRAIL: 4 CẤP ĐỘNG";
      case ADV_TRAIL_ATR_SIMPLE:   return "TRAIL: ATR ĐƠN GIẢN";
      case ADV_TRAIL_HIGH_LOW_BAR: return "TRAIL: ĐỈNH/ĐÁY NẾN";
      case ADV_TRAIL_PARTIAL_STEP: return "TRAIL: BẬC THANG CẮT";
   }
   return "ATR NEO (CHỦ LỰC)";
}

string GetTriggerUnitShortText(ENUM_TRIGGER_UNIT u)
{
   switch(u)
   {
      case UNIT_RR:          return "RR";
      case UNIT_PIPS_POINTS: return "Pts";
      case UNIT_PCT_OF_TP:   return "%TP";
      case UNIT_PRICE:       return "Giá";
   }
   return "RR";
}

string BuildProgressBarText(double curLossPct, double maxLossPct)
{
   double absLoss = (curLossPct < 0.0) ? MathAbs(curLossPct) : 0.0;
   double ratio   = (maxLossPct > 0.0) ? MathMin(1.0, absLoss / maxLossPct) : 0.0;
   int filled     = (int)MathRound(ratio * 10.0);
   string bar     = "[";
   for(int i = 0; i < 10; i++)
      bar += (i < filled) ? "█" : "░";
   bar += "]";
   return bar;
}

//+------------------------------------------------------------------+
//| Kết xuất Ngăn kéo Cấu hình Phụ (Contextual Flyout Drawer 340px)  |
//+------------------------------------------------------------------+
void BuildContextualDrawer(int drawerX, int baseY, int drawerW, int panelH, int rowH, int ctlH, double s)
{
   if(g_drawerMode == DRAWER_CLOSED || g_isMinimized)
      return;

   CreateBox("DrwBg",  drawerX, baseY, drawerW, panelH, C_BG_BODY, C_BORDER);
   CreateBox("DrwHdr", drawerX, baseY, drawerW, rowH + 2, C_BG_HEADER, C_BORDER);

   string drwTitle = "CẤU HÌNH NÂNG CAO";
   if(g_drawerMode == DRAWER_PARTIAL_MATRIX)       drwTitle = "MA TRẬN 10 CẤP PARTIAL TP & SL";
   else if(g_drawerMode == DRAWER_BE_TRAIL_MATRIX) drwTitle = "MA TRẬN 4 CẤP BE & 4 MULTI-TRAIL";
   else if(g_drawerMode == DRAWER_POS_VIRTUAL_BOOK)drwTitle = "SỔ LỆNH ẢO & 5 LỊCH GIAO DỊCH TUẦN";
   else if(g_drawerMode == DRAWER_HOTKEY_STTS)     drwTitle = "BẢNG 23 PHÍM TẮT & CẦU NỐI STTS";

   CreateTxt("DrwTitle", drawerX + 10, baseY + rowH / 2, drwTitle, clrAqua, true);
   int closeW = (int)MathRound(28 * s);
   CreateBtn("Btn_DrwClose", drawerX + drawerW - closeW - 4, baseY + 3, closeW, ctlH, "✕", C_BTN_LOCK, clrWhite, "Đóng ngăn kéo cấu hình phụ");

   int yStart = baseY + rowH + 8;

   // --- NGĂN KÉO 1: MA TRẬN 10 CẤP PARTIAL TP & 10 CẤP PARTIAL SL ---
   if(g_drawerMode == DRAWER_PARTIAL_MATRIX)
   {
      CreateTxt("Drw_M1_Hdr", drawerX + 10, yStart + 8,
                "Cấp | TP (Bật / Mốc / %Đóng) | SL (Bật / -R / %Cắt)", clrGold, true, MathMax(8, InpFontSize - 1));

      int wBtn  = (int)MathRound(38 * s);
      int wEdit = (int)MathRound(44 * s);
      int gap   = (int)MathRound(3 * s);

      for(int i = 0; i < 10; i++)
      {
         int ry = yStart + 20 + i * (ctlH + 3);
         string idxStr = IntegerToString(i + 1);
         CreateTxt("Drw_T_Lbl_" + idxStr, drawerX + 8, ry + ctlH / 2, "C" + idxStr, clrWhite, true);

         // Cột Partial TP tầng i+1
         int xTp = drawerX + (int)MathRound(34 * s);
         string tpUnitStr = GetTriggerUnitShortText(g_tpTiers[i].triggerUnit);
         CreateBtn("Btn_TpTierOn_" + idxStr, xTp, ry, wBtn, ctlH,
                   g_tpTiers[i].enabled ? tpUnitStr : "TẮT",
                   g_tpTiers[i].enabled ? C_BTN_ON : C_BTN_OFF, clrWhite,
                   "Bật/Tắt tầng chốt lời TP" + idxStr);
         CreateEditBox("Ed_TpTrig_" + idxStr, xTp + wBtn + gap, ry, wEdit, ctlH,
                       DoubleToString(g_tpTiers[i].triggerVal, 2), !g_tpTiers[i].enabled,
                       "Mốc kích hoạt TP" + idxStr + " (" + tpUnitStr + ")");
         CreateEditBox("Ed_TpPct_" + idxStr, xTp + wBtn + wEdit + gap * 2, ry, wEdit - 4, ctlH,
                       DoubleToString(g_tpTiers[i].closePct, 0), !g_tpTiers[i].enabled,
                       "% khối lượng đóng tại TP" + idxStr);

         // Cột Partial SL tầng i+1
         int xSl = drawerX + (int)MathRound(190 * s);
         CreateBtn("Btn_SlTierOn_" + idxStr, xSl, ry, wBtn, ctlH,
                   g_slTiers[i].enabled ? "SL" + idxStr : "TẮT",
                   g_slTiers[i].enabled ? C_BTN_ACT : C_BTN_OFF, clrWhite,
                   "Bật/Tắt tầng cắt lỗ từng phần SL" + idxStr);
         CreateEditBox("Ed_SlTrig_" + idxStr, xSl + wBtn + gap, ry, wEdit, ctlH,
                       DoubleToString(g_slTiers[i].triggerVal, 2), !g_slTiers[i].enabled,
                       "Mốc kích hoạt cắt lỗ SL" + idxStr + " (tính theo R âm)");
         CreateEditBox("Ed_SlPct_" + idxStr, xSl + wBtn + wEdit + gap * 2, ry, wEdit - 4, ctlH,
                       DoubleToString(g_slTiers[i].closePct, 0), !g_slTiers[i].enabled,
                       "% khối lượng cắt tại SL" + idxStr);
      }

      int yBot = yStart + 20 + 10 * (ctlH + 3) + 6;
      int halfW = (drawerW - 22) / 2;
      string tpUnitBtn = "ĐƠN VỊ TP: " + GetTriggerUnitShortText(g_tpTiers[0].triggerUnit) + " ▾";
      CreateBtn("Btn_TpUnitCycle", drawerX + 8, yBot, halfW, ctlH, tpUnitBtn, C_BTN_MODE, clrWhite,
                "Đổi đơn vị kích hoạt cho 10 tầng TP (RR / Points / %TP / Giá)");
      CreateBtn("Btn_PartialSlMaster", drawerX + 14 + halfW, yBot, halfW, ctlH,
                g_enPartialSL ? "PARTIAL SL: BẬT" : "PARTIAL SL: TẮT",
                g_enPartialSL ? C_BTN_ON : C_BTN_OFF, clrWhite,
                "Bật/Tắt tổng hệ thống Cắt lỗ từng phần 10 cấp");
   }
   // --- NGĂN KÉO 2: MA TRẬN 4 CẤP BREAKEVEN & 4 CẤP MULTI-TRAIL ---
   else if(g_drawerMode == DRAWER_BE_TRAIL_MATRIX)
   {
      CreateTxt("Drw_M2_H1", drawerX + 10, yStart + 10,
                "BREAKEVEN 4 CẤP (Kích hoạt -> Mức Khóa):", clrGold, true);

      int wBtn  = (int)MathRound(58 * s);
      int wEdit = (int)MathRound(64 * s);
      for(int b = 0; b < 4; b++)
      {
         int ry = yStart + 24 + b * (ctlH + 4);
         string bStr = IntegerToString(b + 1);
         CreateBtn("Btn_BeStgOn_" + bStr, drawerX + 10, ry, wBtn, ctlH,
                   g_beStages[b].enabled ? ("BE Cấp " + bStr) : ("BE" + bStr + " TẮT"),
                   g_beStages[b].enabled ? C_BTN_ON : C_BTN_OFF, clrWhite);
         CreateTxt("Drw_BeArr_" + bStr, drawerX + 14 + wBtn + wEdit, ry + ctlH / 2, "➔ Khóa:", clrWhite, false);
         CreateEditBox("Ed_BeTrig_" + bStr, drawerX + 14 + wBtn, ry, wEdit, ctlH,
                       DoubleToString(g_beStages[b].triggerVal, 2), !g_beStages[b].enabled);
         CreateEditBox("Ed_BeLock_" + bStr, drawerX + 18 + wBtn + wEdit + (int)MathRound(54 * s), ry, wEdit, ctlH,
                       DoubleToString(g_beStages[b].lockVal, 2), !g_beStages[b].enabled);
      }

      int yMid = yStart + 28 + 4 * (ctlH + 4);
      int halfW = (drawerW - 22) / 2;
      CreateBtn("Btn_CommonBeToggle", drawerX + 8, yMid, halfW, ctlH,
                g_enCommonBe ? "COMMON BE: BẬT" : "COMMON BE: TẮT",
                g_enCommonBe ? C_BTN_ON : C_BTN_OFF, clrWhite,
                "Tính và vẽ đường Hòa vốn chung toàn rổ lệnh (VWAP + Phí + Swap)");
      CreateBtn("Btn_LockProfitToggle", drawerX + 14 + halfW, yMid, halfW, ctlH,
                g_enLock ? "LOCK PROFIT: BẬT" : "LOCK PROFIT: TẮT",
                g_enLock ? C_BTN_ON : C_BTN_OFF, clrWhite,
                "Khóa lợi nhuận tối thiểu (+LockLvl R khi đạt LockTrig R)");

      int yTrHdr = yMid + ctlH + 14;
      CreateTxt("Drw_M2_H2", drawerX + 10, yTrHdr,
                "MULTI-TRAIL 4 CẤP (Lãi Pts | Cách Pts | Bước Pts):", clrAqua, true);

      int wSmall = (int)MathRound(56 * s);
      for(int m = 0; m < 4; m++)
      {
         int ry = yTrHdr + 14 + m * (ctlH + 4);
         string mStr = IntegerToString(m + 1);
         CreateBtn("Btn_MTrOn_" + mStr, drawerX + 10, ry, wBtn, ctlH,
                   g_multiTrailStages[m].enabled ? ("Nấc " + mStr + ": ON") : ("Nấc " + mStr + ": OFF"),
                   g_multiTrailStages[m].enabled ? C_BTN_MODE : C_BTN_OFF, clrWhite);
         CreateEditBox("Ed_MTrGain_" + mStr, drawerX + 16 + wBtn, ry, wSmall, ctlH,
                       DoubleToString(g_multiTrailStages[m].triggerPts, 0), !g_multiTrailStages[m].enabled);
         CreateEditBox("Ed_MTrDist_" + mStr, drawerX + 20 + wBtn + wSmall, ry, wSmall, ctlH,
                       DoubleToString(g_multiTrailStages[m].distPts, 0), !g_multiTrailStages[m].enabled);
         CreateEditBox("Ed_MTrStep_" + mStr, drawerX + 24 + wBtn + wSmall * 2, ry, wSmall, ctlH,
                       DoubleToString(g_multiTrailStages[m].stepPts, 0), !g_multiTrailStages[m].enabled);
      }
   }
   // --- NGĂN KÉO 3: SỔ LỆNH CHỜ ẢO & BẢNG 5 TÁC VỤ LỊCH TUẦN ---
   else if(g_drawerMode == DRAWER_POS_VIRTUAL_BOOK)
   {
      CreateTxt("Drw_M3_H1", drawerX + 10, yStart + 10, "SỔ LỆNH CHỜ ẢO ĐANG HOẠT ĐỘNG:", clrGold, true);
      int shownV = 0;
      for(int v = 0; v < 20 && shownV < 4; v++)
      {
         if(g_virtualOrders[v].state == VORD_INACTIVE)
            continue;
         int ry = yStart + 24 + shownV * (ctlH + 3);
         string vModeStr = (g_virtualOrders[v].mode == ENTRY_MODE_LPO) ? "V-LPO"
                           : ((g_virtualOrders[v].mode == ENTRY_MODE_STOP_LIMIT) ? "V-STPLIM"
                           : ((g_virtualOrders[v].mode == ENTRY_MODE_STOP) ? "V-STOP" : "V-LIMIT"));
         string vDesc = StringFormat("#%d %s %s @%s (SL:%s)",
                                     v + 1, vModeStr, g_virtualOrders[v].isBuy ? "BUY" : "SELL",
                                     DoubleToString(g_virtualOrders[v].entryPrice, _Digits),
                                     DoubleToString(g_virtualOrders[v].slPrice, _Digits));
         CreateTxt("Drw_VOrd_" + IntegerToString(shownV), drawerX + 10, ry + ctlH / 2, vDesc, clrAqua, false);
         shownV++;
      }
      if(shownV == 0)
         CreateTxt("Drw_VOrd_Empty", drawerX + 10, yStart + 34,
                   "• Chưa có lệnh chờ ảo nào. Bấm [ARM LỆNH ẢO] ở Tab TRADE.", clrSilver, false);

      int yTaskHdr = yStart + 135;
      CreateTxt("Drw_M3_H2", drawerX + 10, yTaskHdr,
                "LỊCH TUẦN 5 TÁC VỤ (Bật | Giờ Server | Hành động):", clrLime, true);

      int wTBtn = (int)MathRound(48 * s);
      int wTEd  = (int)MathRound(58 * s);
      int wAct  = drawerW - wTBtn - wTEd - 28;
      for(int t = 0; t < 5; t++)
      {
         int ry = yTaskHdr + 16 + t * (ctlH + 4);
         string tStr = IntegerToString(t + 1);
         CreateBtn("Btn_WTaskOn_" + tStr, drawerX + 10, ry, wTBtn, ctlH,
                   g_timeTasks[t].enabled ? ("T" + tStr + ": ON") : ("T" + tStr + ": OFF"),
                   g_timeTasks[t].enabled ? C_BTN_ON : C_BTN_OFF, clrWhite);
         CreateEditBox("Ed_WTaskTime_" + tStr, drawerX + 14 + wTBtn, ry, wTEd, ctlH,
                       g_timeTasks[t].timeStr, !g_timeTasks[t].enabled);

         string actLbl = "ĐÓNG SYMBOL";
         if(g_timeTasks[t].action == WEEKLY_OPEN_BUY)            actLbl = "MỞ BUY MKT";
         else if(g_timeTasks[t].action == WEEKLY_OPEN_SELL)      actLbl = "MỞ SELL MKT";
         else if(g_timeTasks[t].action == WEEKLY_CLOSE_BUY)      actLbl = "ĐÓNG LỆNH BUY";
         else if(g_timeTasks[t].action == WEEKLY_CLOSE_SELL)     actLbl = "ĐÓNG LỆNH SELL";
         else if(g_timeTasks[t].action == WEEKLY_DELETE_PENDING) actLbl = "XÓA LỆNH CHỜ";

         CreateBtn("Btn_WTaskAct_" + tStr, drawerX + 18 + wTBtn + wTEd, ry, wAct, ctlH,
                   actLbl, C_BTN_MODE, clrWhite);
      }
   }
   // --- NGĂN KÉO 4: BẢNG 23 PHÍM TẮT & CẦU NỐI CHỈ BÁO STTS ---
   else if(g_drawerMode == DRAWER_HOTKEY_STTS)
   {
      CreateTxt("Drw_M4_H1", drawerX + 10, yStart + 10, "TÓM TẮT 23 PHÍM TẮT ĐIỀU KHIỂN NHANH:", clrGold, true);
      CreateTxt("Drw_HK_1",  drawerX + 10, yStart + 32,
                StringFormat("• Mua/Bán: [%s] / [%s] | OCO: [%s] | Đổi Kiểu: [%s]",
                             InpHotkeyBuy, InpHotkeySell, InpHotkeyOCO, InpHotkeyPendingOrder), clrWhite, false);
      CreateTxt("Drw_HK_2",  drawerX + 10, yStart + 52,
                StringFormat("• Dời BE: [%s] | Cắt 50%%: [%s] | Đóng Hết: [%s]",
                             InpHotkeyBreakEven, InpHotkeyClosePartial, InpHotkeyCloseAll), clrWhite, false);
      CreateTxt("Drw_HK_3",  drawerX + 10, yStart + 72,
                StringFormat("• Đóng Lời/Lỗ: [%s] / [%s] | Đóng Buy/Sell: [%s] / [%s]",
                             InpHotkeyCloseWinners, InpHotkeyCloseLosers, InpHotkeyCloseBuy, InpHotkeyCloseSell), clrWhite, false);
      CreateTxt("Drw_HK_4",  drawerX + 10, yStart + 92,
                StringFormat("• Sizer Buy/Sell: [%s] / [%s] | Ghim SL/TP: [%s] / [%s]",
                             InpHotkeyDrawBuy, InpHotkeyDrawSell, InpHotkeyPinSL, InpHotkeyPinTP), clrWhite, false);
      CreateTxt("Drw_HK_5",  drawerX + 10, yStart + 112,
                StringFormat("• Symbol Kế/Trước: [%s] / [%s] | Ẩn/Hiện Bảng: [%s]",
                             InpHotkeyNextSymbol, InpHotkeyPreviousSymbol, InpHotkeyTogglePanel), clrAqua, false);

      int yStts = yStart + 145;
      CreateTxt("Drw_M4_H2", drawerX + 10, yStts, "CẦU NỐI SMART TREND TRADING SYSTEM (STTS):", clrLime, true);
      string sttsModeTxt = (g_sttsBridgeMode == STTS_BRIDGE_OFF) ? "STTS BRIDGE: TẮT ▾"
                           : ((g_sttsBridgeMode == STTS_BRIDGE_FILTER_HUD) ? "STTS: COPILOT FILTER ▾" : "STTS: AUTO SIGNAL TG ▾");
      CreateBtn("Btn_SttsMode", drawerX + 10, yStts + 16, drawerW - 20, ctlH + 2,
                sttsModeTxt, (g_sttsBridgeMode == STTS_BRIDGE_OFF) ? C_BTN_OFF : C_BTN_ON, clrWhite,
                "Chuyển đổi chế độ kết nối với chỉ báo Smart Trend Trading System (103515)");

      string trendStr = (g_sttsCurrentTrend > 0) ? "▲ XU HƯỚNG TĂNG (BULLISH)"
                        : ((g_sttsCurrentTrend < 0) ? "▼ XU HƯỚNG GIẢM (BEARISH)" : "• TRUNG LẬP / CHỜ TÍN HIỆU");
      CreateTxt("Drw_Stts_Stat", drawerX + 10, yStts + 52, "Trạng thái STTS: " + trendStr,
                (g_sttsCurrentTrend > 0) ? clrLime : ((g_sttsCurrentTrend < 0) ? clrTomato : clrSilver), true);
   }
}

//+------------------------------------------------------------------+
//| Xây dựng toàn bộ Khung Điều khiển Chính (560x620) & Ngăn kéo Phụ |
//+------------------------------------------------------------------+
void RebuildCleanPanel(bool clearBeforeBuild)
{
   if(clearBeforeBuild)
      ObjectsDeleteAll(0, PREFIX);

   int dpi = TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   double s = ((dpi > 96) ? (dpi / 96.0) : 1.0) * g_uiScale;

   int panelW  = (int)MathRound(560 * s);
   int drawerW = (int)MathRound(340 * s);
   int rowH    = (int)MathRound(26 * s);
   int ctlH    = (int)MathRound(20 * s);
   int editW   = (int)MathRound(58 * s);
   int smallW  = (int)MathRound(50 * s);
   int btnW    = (int)MathRound(112 * s);

   g_panelW  = panelW;
   g_drawerW = drawerW;
   g_headerH = rowH + 2;
   g_panelH  = g_isMinimized ? (rowH * 4 + 10) : (rowH * 20 + 18);

   ClampPanelCoordinates();
   int baseX = g_panelX;
   int baseY = g_panelY;

   // --- 1. THANH TIÊU ĐỀ (HEADER BAR) ---
   CreateBox("HdrBg", baseX, baseY, panelW, rowH + 2, g_isDraggingPanel ? C_BG_DRAG : C_BG_HEADER, C_BORDER);
   int spreadPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   string hdrTitleTxt = g_isDraggingPanel ? "ĐANG DI CHUYỂN BẢNG ĐIỀU KHIỂN..."
                        : StringFormat("TRADEDESK PRO v12  •  %s · %s  |  Spd: %d đ", _Symbol, GetTfShortName(_Period), spreadPts);
   CreateTxt("HdrTitle", baseX + 10, baseY + rowH / 2, hdrTitleTxt, g_isDraggingPanel ? clrYellow : clrWhite, true);

   int minW  = (int)MathRound(28 * s);
   int cornW = (int)MathRound(54 * s);
   int drwBtnW = (int)MathRound(68 * s);
   CreateBtn("Btn_Min",  baseX + panelW - minW - 4, baseY + 3, minW, ctlH,
             g_isMinimized ? "[+]" : "[-]", C_BTN_OFF, clrWhite, "Thu gọn / Mở rộng bảng điều khiển");
   CreateBtn("Btn_Area", baseX + panelW - minW - cornW - 8, baseY + 3, cornW, ctlH,
             "GÓC", C_BTN_MODE, clrWhite, "Chuyển nhanh vị trí bảng qua 4 góc biểu đồ");
   CreateBtn("Btn_DrawerToggle", baseX + panelW - minW - cornW - drwBtnW - 12, baseY + 3, drwBtnW, ctlH,
             (g_drawerMode != DRAWER_CLOSED) ? "ĐÓNG ◂" : "MA TRẬN ▸",
             (g_drawerMode != DRAWER_CLOSED) ? C_BTN_ON : C_TAB_IDLE, clrWhite,
             "Đóng/Mở Ngăn kéo Cấu hình Ma trận 10 tầng TP/SL, 4 BE & Sổ lệnh ảo");

   // --- 2. THANH TRẠNG THÁI KÉP (TELEMETRY HUD — LUÔN HIỆN KỂ CẢ KHI THU GỌN) ---
   int yHud = baseY + rowH + 4;
   CreateBox("HudCard", baseX + 6, yHud, panelW - 12, rowH * 3 + 2, C_BG_HUD, clrTeal);

   CreateTxt("Hud_Line1", baseX + 14, yHud + (int)(13 * s), "ĐANG KIỂM TRA TRẠNG THÁI...", clrLime, true);
   CreateBtn("Btn_ForceLock", baseX + panelW - btnW - 12, yHud + 3, btnW, ctlH,
             g_accountSwitchHold ? (g_accountHoldRiskDataReady ? "XÁC NHẬN TK" : "CHỜ DỮ LIỆU")
                                 : (g_manualForceLock ? "MỞ KHÓA TAY" : "KHÓA NGAY"),
             g_accountSwitchHold ? (g_accountHoldRiskDataReady ? C_BTN_ACT : C_BTN_LOCK)
                                 : (g_manualForceLock ? C_BTN_LOCK : C_BTN_ACT), clrWhite,
             "Khóa khẩn cấp toàn bộ giao dịch hoặc xác nhận tài khoản mới");

   CreateTxt("Hud_Line2L", baseX + 14, yHud + (int)(38 * s), "KHỐI LƯỢNG: ...", clrWhite, true);
   CreateTxt("Hud_Line2R", baseX + (int)MathRound(278 * s), yHud + (int)(38 * s), "TP1/CÒN LẠI: ...", clrAqua, true);

   CreateTxt("Hud_Line3L", baseX + 14, yHud + (int)(62 * s), "ATR TRAIL: ...", clrGold, true);
   CreateTxt("Hud_Line3R", baseX + (int)MathRound(278 * s), yHud + (int)(62 * s), "TRẠNG THÁI: ...", clrGold, true);

   if(g_isMinimized)
   {
      ChartRedraw(0);
      return;
   }

   bool bodyIsNew = (ObjectFind(0, PREFIX + "BodyBg") < 0);
   CreateBox("BodyBg", baseX, baseY + rowH + 1, panelW, rowH * 19 + 14, C_BG_BODY, C_BORDER);
   // [v12.1.1] BodyBg vừa tạo sẽ ĐÈ LÊN HUD (kể cả nút XÁC NHẬN TK / KHÓA NGAY).
   // MT5 vẽ theo thứ tự tạo, nên phải xóa HUD để tạo lại phía trên BodyBg.
   if(bodyIsNew)
   {
      string hudObjs[7] = {"HudCard", "Hud_Line1", "Btn_ForceLock", "Hud_Line2L", "Hud_Line2R", "Hud_Line3L", "Hud_Line3R"};
      for(int hi = 0; hi < 7; hi++)
         ObjectDelete(0, PREFIX + hudObjs[hi]);
   }
   CreateBox("HudCard", baseX + 6, yHud, panelW - 12, rowH * 3 + 2, C_BG_HUD, clrTeal);
   CreateTxt("Hud_Line1", baseX + 14, yHud + (int)(13 * s), "ĐANG KIỂM TRA TRẠNG THÁI...", clrLime, true);
   CreateBtn("Btn_ForceLock", baseX + panelW - btnW - 12, yHud + 3, btnW, ctlH,
             g_accountSwitchHold ? (g_accountHoldRiskDataReady ? "XÁC NHẬN TK" : "CHỜ DỮ LIỆU")
                                 : (g_manualForceLock ? "MỞ KHÓA TAY" : "KHÓA NGAY"),
             g_accountSwitchHold ? (g_accountHoldRiskDataReady ? C_BTN_ACT : C_BTN_LOCK)
                                 : (g_manualForceLock ? C_BTN_LOCK : C_BTN_ACT), clrWhite);
   CreateTxt("Hud_Line2L", baseX + 14, yHud + (int)(38 * s), "KHỐI LƯỢNG: ...", clrWhite, true);
   CreateTxt("Hud_Line2R", baseX + (int)MathRound(278 * s), yHud + (int)(38 * s), "TP1/CÒN LẠI: ...", clrAqua, true);
   CreateTxt("Hud_Line3L", baseX + 14, yHud + (int)(62 * s), "ATR TRAIL: ...", clrGold, true);
   CreateTxt("Hud_Line3R", baseX + (int)MathRound(278 * s), yHud + (int)(62 * s), "TRẠNG THÁI: ...", clrGold, true);

   // --- 3. THANH ĐIỀU HƯỚNG 5 TAB ---
   int yTab   = baseY + rowH * 4 + 10;
   int tabW   = (panelW - 30) / 5;
   int tabGap = 4;
   CreateBtn("Tab_Pos",      baseX + 6,                        yTab, tabW, ctlH + 3, "1. TRADE",    (g_activeTab == TAB_POSITION) ? C_TAB_ACTIVE : C_TAB_IDLE, clrWhite);
   CreateBtn("Tab_Trail",    baseX + 6 + (tabW + tabGap),      yTab, tabW, ctlH + 3, "2. MANAGE",   (g_activeTab == TAB_TRAILING) ? C_TAB_ACTIVE : C_TAB_IDLE, clrWhite);
   CreateBtn("Tab_Risk",     baseX + 6 + (tabW + tabGap) * 2,  yTab, tabW, ctlH + 3, "3. GUARD",    (g_activeTab == TAB_RISKNEWS) ? C_TAB_ACTIVE : C_TAB_IDLE, clrWhite);
   CreateBtn("Tab_Auto",     baseX + 6 + (tabW + tabGap) * 3,  yTab, tabW, ctlH + 3, "4. AUTOMATE", (g_activeTab == TAB_AUTOMATE) ? C_TAB_ACTIVE : C_TAB_IDLE, clrWhite);
   CreateBtn("Tab_Settings", baseX + 6 + (tabW + tabGap) * 4,  yTab, tabW, ctlH + 3, "5. SETTINGS", (g_activeTab == TAB_SETTINGS) ? C_TAB_ACTIVE : C_TAB_IDLE, clrWhite);

   // --- 4. VÙNG NỘI DUNG TAB (TAB VIEWPORT) ---
   int yContent = baseY + rowH * 5 + 14;
   CreateBox("TabCard", baseX + 6, yContent, panelW - 12, rowH * 11 + 8, C_BG_CARD, C_BORDER);

   int colEdit1 = baseX + (int)MathRound(226 * s);
   int colEdit2 = baseX + (int)MathRound(292 * s);
   int col3_1   = baseX + (int)MathRound(204 * s);
   int col3_2   = baseX + (int)MathRound(260 * s);
   int col3_3   = baseX + (int)MathRound(316 * s);
   int colBtn   = baseX + panelW - btnW - 12;

   if(g_activeTab == TAB_POSITION)
   {
      int r = 0, y = yContent + r * rowH + 6;
      string slModeTxt = (g_slMode == SL_MODE_ATR_FIRST)  ? "SL: ATR ĐẦU ▾"
                       : ((g_slMode == SL_MODE_ATR_LINE)  ? "SL: ĐƯỜNG ATR ▾"
                       : ((g_slMode == SL_MODE_POINTS)    ? "SL: ĐIỂM CỐ ĐỊNH ▾"
                       : ((g_slMode == SL_MODE_FIXED_CASH)? "SL: TIỀN CỐ ĐỊNH ▾" : "SL: KÉO THẢ ▾")));
      CreateTxt("T1_L1", baseX + 14, y + rowH / 2,
                (g_riskInputMode == RISK_INPUT_CASH ? "Risk tiền ($) | Tỷ lệ TP (R):" : "Risk (%) | Tỷ lệ TP (R):"), clrWhite, false);
      CreateEditBox("Ed_RiskPct", colEdit1, y + 2, editW, ctlH,
                    DoubleToString(g_riskInputMode == RISK_INPUT_CASH ? g_riskFixedCash : g_riskPct, 2));
      CreateEditBox("Ed_RR", colEdit2, y + 2, editW, ctlH, DoubleToString(g_targetRR, 2));
      CreateBtn("Btn_SlMode", colBtn, y + 2, btnW, ctlH, slModeTxt, C_BTN_MODE, clrWhite,
                "Chọn nguồn tính khoảng cách Stop Loss (5 chế độ)");

      r = 1; y = yContent + r * rowH + 6;
      CreateTxt("T1_L2", baseX + 14, y + rowH / 2, "Cơ sở vốn tính Risk (8 chế độ):", clrAqua, true);
      CreateBtn("Btn_RiskMode", colEdit1, y + 2, panelW - (colEdit1 - baseX) - 12, ctlH,
                "CƠ SỞ VỐN: " + GetRiskInputModeText() + " ▾", C_BTN_MODE, clrWhite,
                "Chuyển đổi giữa 8 cơ sở vốn tính ngân sách rủi ro của Trade Assistant");

      r = 2; y = yContent + r * rowH + 6;
      string ruleTxt = (g_volRule == RULE_KEEP_DIST_CALC_CASH) ? "GIỮ KHOẢNG SL/TP -> TÍNH TIỀN ($)" : "CO GIÃN KHOẢNG SL THEO LOT & RISK";
      CreateTxt("T1_L3", baseX + 14, y + rowH / 2, "Quy tắc SL/TP khi đổi Lot:", clrWhite, false);
      CreateBtn("Btn_VolRule", colEdit1, y + 2, panelW - (colEdit1 - baseX) - 12, ctlH,
                ruleTxt, (g_volRule == RULE_KEEP_DIST_CALC_CASH) ? C_BTN_ON : C_BTN_ACT, clrWhite);

      r = 3; y = yContent + r * rowH + 6;
      string multiTxt = (g_multiMode == MULTI_BASKET_VWAP) ? "GỘP RỔ LỆNH THEO GIÁ VWAP" : "QUẢN LÝ TÁCH RIÊNG TỪNG LỆNH";
      CreateTxt("T1_L4", baseX + 14, y + rowH / 2, "Chế độ nhiều lệnh cùng lúc:", clrYellow, true);
      CreateBtn("Btn_MultiMode", colEdit1, y + 2, panelW - (colEdit1 - baseX) - 12, ctlH,
                multiTxt, (g_multiMode == MULTI_BASKET_VWAP) ? C_TAB_ACTIVE : C_BTN_OFF, clrWhite);

      r = 4; y = yContent + r * rowH + 6;
      CreateTxt("T1_L5", baseX + 14, y + rowH / 2, "SL (điểm) | Đệm (đ) | Phí ($/lot):", clrWhite, false);
      CreateEditBox("Ed_ManSlPts", col3_1, y + 2, smallW, ctlH, IntegerToString(g_manualSlPts));
      CreateEditBox("Ed_BufPts",   col3_2, y + 2, smallW, ctlH, IntegerToString(g_bufferPts));
      CreateEditBox("Ed_CommLot",  col3_3, y + 2, smallW, ctlH, DoubleToString(g_commPerLot, 1));
      CreateBtn("Btn_AutoSlTp", colBtn, y + 2, btnW, ctlH,
                g_autoSlTp ? "GẮN SL ĐẦU: BẬT" : "GẮN SL ĐẦU: TẮT",
                g_autoSlTp ? C_BTN_ON : C_BTN_OFF, clrWhite);

      r = 5; y = yContent + r * rowH + 6;
      string trailQuickTxt = (g_trailStyle == TRAIL_STYLE_AUTO_ATR) ? "AUTO TRAIL"
                             : ((g_trailStyle == TRAIL_STYLE_BE_FLOAT) ? "CHỜ DỜI BE" : "SL TAY 100%");
      color trailQuickClr  = (g_trailStyle == TRAIL_STYLE_AUTO_ATR) ? C_BTN_ON
                             : ((g_trailStyle == TRAIL_STYLE_BE_FLOAT) ? C_BTN_ACT : C_BTN_OFF);
      int wSmallBtn = (int)MathRound(84 * s);
      CreateTxt("T1_L6", baseX + 14, y + rowH / 2, "Chế độ SL | Nhật ký | Thước:", clrLime, true);
      CreateBtn("Btn_Trail",     col3_1,                  y + 2, wSmallBtn, ctlH, trailQuickTxt, trailQuickClr, clrWhite);
      CreateBtn("Btn_Journal",   col3_1 + wSmallBtn + 4,  y + 2, wSmallBtn, ctlH, g_showJournal ? "NHẬT KÝ: BẬT" : "NHẬT KÝ: TẮT", g_showJournal ? C_BTN_ON : C_BTN_OFF, clrWhite);
      CreateBtn("Btn_ShowSizer", colBtn,                  y + 2, btnW,      ctlH, g_showSizer ? "THƯỚC: HIỆN" : "THƯỚC: ẨN", g_showSizer ? C_BTN_ON : C_BTN_OFF, clrWhite);

      r = 6; y = yContent + r * rowH + 6;
      CreateTxt("T1_L7", baseX + 14, y + rowH / 2, "Kiểu lệnh (6 kiểu) | Hướng Setup:", clrWhite, true);
      int modeW = (panelW - (colEdit1 - baseX) - 18) / 2;
      CreateBtn("Btn_EntryMode", colEdit1,             y + 2, modeW, ctlH, GetEntryModeBtnLabel(), C_BTN_MODE, clrWhite,
                "Xoay vòng 6 kiểu vào lệnh: Market, Limit, Stop, LPO 2 Pha, Buy/Sell Stop-Limit, OCO");
      CreateBtn("Btn_EntrySide", colEdit1 + modeW + 4, y + 2, modeW, ctlH,
                (g_tradeSide == SIDE_LONG) ? "HƯỚNG: ▲ BUY" : "HƯỚNG: ▼ SELL",
                (g_tradeSide == SIDE_LONG) ? C_BTN_BUY : C_BTN_SELL, clrWhite);

      r = 7; y = yContent + r * rowH + 6;
      CreateTxt("T1_L8", baseX + 14, y + rowH / 2, "LPO (đ) | StopLim (đ) | MaxLot:", clrWhite, false);
      CreateEditBox("Ed_PullbackPts",  col3_1, y + 2, smallW, ctlH, IntegerToString(g_pullbackPoints),   false, "Khoảng cách bám sóng hồi cho lệnh LPO 2 pha (Points)");
      CreateEditBox("Ed_StopLimPts",   col3_2, y + 2, smallW, ctlH, IntegerToString(g_stopLimitOffsetPts),false, "Khoảng cách lệch giữa giá Stop và giá Limit cho lệnh Stop-Limit (Points)");
      CreateEditBox("Ed_MaxChildLot",  col3_3, y + 2, smallW, ctlH, DoubleToString(g_maxLotPerOrder, 2),  false, "Lot tối đa mỗi lệnh con khi tự động chia lệnh lớn (0 = Max sàn)");
      CreateBtn("Btn_ArmVirtual", colBtn, y + 2, btnW, ctlH,
                g_virtualPendingActive ? "HỦY LỆNH ẢO" : "ARM LỆNH ẢO",
                g_virtualPendingActive ? C_BTN_LOCK : C_BTN_MODE, clrWhite,
                "Đăng ký lệnh chờ ảo (V-Limit, V-Stop, V-LPO 2 pha, V-StopLimit) vào sổ lệnh ảo");

      r = 8; y = yContent + r * rowH + 6;
      CreateTxt("T1_L9", baseX + 14, y + rowH / 2, "Chế độ OCO (100% Risk/nhánh):", clrAqua, true);
      CreateBtn("Btn_OcoModeCycle", colEdit1, y + 2, modeW, ctlH, GetOcoModeBtnLabel(), C_BTN_MODE, clrWhite,
                "Chọn 1 trong 5 chế độ OCO (Stop-Stop, Limit-Limit, Buy Lim+Stp, Sell Lim+Stp, Gom lệnh)");
      CreateBtn("Btn_CreateOco",    colEdit1 + modeW + 4, y + 2, modeW, ctlH, "ĐẶT CẶP OCO NGAY", C_BTN_ACT, clrWhite);

      r = 9; y = yContent + r * rowH + 6;
      CreateTxt("T1_L10", baseX + 14, y + rowH / 2, "Lot tay dự kiến (0 = theo Gợi ý):", clrWhite, false);
      CreateEditBox("Ed_ManualLot", colEdit1, y + 2, editW, ctlH, DoubleToString(g_enteredManualLot, 2));
      CreateBtn("Btn_OpenDrawerMatrix", colEdit2 + 8, y + 2, panelW - (colEdit2 - baseX) - 20, ctlH,
                "MỞ MA TRẬN 10 TP / 10 SL ▸", C_TAB_ACTIVE, clrWhite);
   }
   else if(g_activeTab == TAB_TRAILING)
   {
      int r = 0, y = yContent + r * rowH + 6;
      CreateTxt("T2_L1", baseX + 14, y + rowH / 2, "ATR Neo (Chu kỳ | 1stMul | Hệ số):", clrAqua, true);
      CreateEditBox("Ed_AtrPer",   col3_1, y + 2, smallW, ctlH, IntegerToString(g_atrLength));
      CreateEditBox("Ed_FirstMul", col3_2, y + 2, smallW, ctlH, DoubleToString(g_customValueForFirstDay, 2));
      CreateEditBox("Ed_AtrMul",   col3_3, y + 2, smallW, ctlH, DoubleToString(g_atrMultiplier, 2));
      CreateBtn("Btn_ShowPlot", colBtn, y + 2, btnW, ctlH,
                g_showAtrPlot ? "VẼ LINE: BẬT" : "VẼ LINE: TẮT",
                g_showAtrPlot ? C_BTN_ON : C_BTN_OFF, clrWhite);

      r = 1; y = yContent + r * rowH + 6;
      string dateLbl = g_autoSyncDate ? "Ngày Neo [TỰ ĐỘNG] | Khung ATR:" : "Ngày Neo [CỐ ĐỊNH] | Khung ATR:";
      CreateTxt("T2_L2", baseX + 14, y + rowH / 2, dateLbl, g_autoSyncDate ? clrLime : clrYellow, true);
      CreateEditBox("Ed_Yr", col3_1, y + 2, smallW, ctlH, IntegerToString(g_entryDateYear));
      CreateEditBox("Ed_Mo", col3_2, y + 2, smallW, ctlH, IntegerToString(g_entryDateMonth));
      CreateEditBox("Ed_Dy", col3_3, y + 2, smallW, ctlH, IntegerToString(g_entryDateDay));
      CreateBtn("Btn_AtrTf", colBtn, y + 2, btnW, ctlH, GetAtrTfBtnLabel(), C_BTN_MODE, clrWhite);

      r = 2; y = yContent + r * rowH + 6;
      int wAnti1 = (int)MathRound(148 * s);
      int wAnti2 = (int)MathRound(126 * s);
      string sweepBtnTxt = (g_sweepMode == SWEEP_3LAYER_20PCT_1R)   ? "3 TẦNG (20% 1R)"
                         : ((g_sweepMode == SWEEP_WAIT_CANDLE_CLOSE)? "CHỜ NẾN ĐÓNG (T1)" : "SL CỨNG TRÊN LINE");
      color sweepBtnClr  = (g_sweepMode == SWEEP_3LAYER_20PCT_1R)   ? C_BTN_ON
                         : ((g_sweepMode == SWEEP_WAIT_CANDLE_CLOSE)? C_TAB_ACTIVE : C_BTN_OFF);

      CreateTxt("T2_L3", baseX + 14, y + rowH / 2, "Chống quét râu & Nguồn ATR:", clrLime, true);
      CreateBtn("Btn_SweepMode", col3_1,              y + 2, wAnti1, ctlH, sweepBtnTxt, sweepBtnClr, clrWhite);
      CreateBtn("Btn_AtrSrc",    col3_1 + wAnti1 + 6, y + 2, wAnti2, ctlH,
                (g_atrSource == ATR_SRC_CLOSE_SWING) ? "NEO: CLOSE+SWING" : "NEO: HIGH/LOW",
                (g_atrSource == ATR_SRC_CLOSE_SWING) ? C_BTN_MODE : C_BTN_OFF, clrWhite);

      r = 3; y = yContent + r * rowH + 6;
      string trailBtnTxt = (g_trailStyle == TRAIL_STYLE_AUTO_ATR) ? "TRAIL: BẬT (>=R)"
                         : ((g_trailStyle == TRAIL_STYLE_BE_FLOAT)? "CHỜ DỜI BE" : "SL TAY 100%");
      color trailBtnClr  = (g_trailStyle == TRAIL_STYLE_AUTO_ATR) ? C_BTN_ON
                         : ((g_trailStyle == TRAIL_STYLE_BE_FLOAT)? C_BTN_ACT : C_BTN_OFF);
      CreateTxt("T2_L4", baseX + 14, y + rowH / 2, "Bắt đầu Trail (R) | Đệm T3 (%1R):", clrWhite, false);
      CreateEditBox("Ed_TrailRR",   colEdit1, y + 2, editW, ctlH, DoubleToString(g_trailStartRR, 2));
      CreateEditBox("Ed_TierPct1R", colEdit2, y + 2, editW, ctlH, DoubleToString(g_tierPctOf1R, 0), (g_sweepMode == SWEEP_HARD_SL_ON_LINE));
      CreateBtn("Btn_Trail", colBtn, y + 2, btnW, ctlH, trailBtnTxt, trailBtnClr, clrWhite);

      r = 4; y = yContent + r * rowH + 6;
      string tp1BeTxt = g_enPartial ? (g_enBe ? "TP1 + DỜI BE" : "TP1: GIỮ SL") : (g_enBe ? "CHỈ DỜI BE" : "TP1 & BE: TẮT");
      color  tp1BeClr = g_enPartial ? (g_enBe ? C_BTN_ACT : C_BTN_ON) : (g_enBe ? C_TAB_ACTIVE : C_BTN_OFF);
      CreateTxt("T2_L5", baseX + 14, y + rowH / 2, "TP1 (R | %Lot) | +Điểm BE:", clrWhite, false);
      CreateEditBox("Ed_PartRR",  col3_1, y + 2, smallW, ctlH, DoubleToString(g_partialRR, 1));
      CreateEditBox("Ed_PartPct", col3_2, y + 2, smallW, ctlH, DoubleToString(g_partialPct, 0));
      CreateEditBox("Ed_BePts",   col3_3, y + 2, smallW, ctlH, IntegerToString(g_bePoints), !g_enBe);
      CreateBtn("Btn_Be", colBtn, y + 2, btnW, ctlH, tp1BeTxt, tp1BeClr, clrWhite);

      r = 5; y = yContent + r * rowH + 6;
      CreateTxt("T2_L6", baseX + 14, y + rowH / 2, "Phương pháp Trailing (9 kiểu):", clrAqua, true);
      CreateBtn("Btn_AdvancedTrail", colEdit1, y + 2, panelW - (colEdit1 - baseX) - 12, ctlH,
                GetAdvTrailBtnLabel() + " ▾", (g_advTrailMode == ADV_TRAIL_OFF) ? C_BTN_ON : C_BTN_MODE, clrWhite,
                "Chọn 1 trong 9 thuật toán Trailing Stop (ATR Neo, MA, Fractal, PSAR, Pips, Multi-4, ATR Simple, High/Low, Partial Step)");

      r = 6; y = yContent + r * rowH + 6;
      int halfM = (panelW - 28) / 2;
      CreateBtn("Btn_OpenDrawerMatrix",  baseX + 10,             y + 2, halfM, ctlH + 2,
                "MA TRẬN 10 TP / 10 SL ▸", (g_drawerMode == DRAWER_PARTIAL_MATRIX) ? C_BTN_ON : C_TAB_ACTIVE, clrWhite);
      CreateBtn("Btn_OpenDrawerBeTrail", baseX + 16 + halfM,     y + 2, halfM, ctlH + 2,
                "CẤU HÌNH 4 BE & 4 TRAIL ▸", (g_drawerMode == DRAWER_BE_TRAIL_MATRIX) ? C_BTN_ON : C_BTN_MODE, clrWhite);

      r = 7; y = yContent + r * rowH + 8;
      string commonBeStr = (g_commonBePrice > 0.0) ? DoubleToString(g_commonBePrice, _Digits) : "Chưa có rổ lệnh";
      CreateTxt("T2_L8", baseX + 14, y + rowH / 2,
                StringFormat("Common BE (VWAP+Phí): %s | T1 cứu: %d | T2 cắt: %d",
                             commonBeStr, g_tier1SavedCount, g_tier2HalfCutCount), clrGold, true);
   }
   else if(g_activeTab == TAB_RISKNEWS)
   {
      int r = 0, y = yContent + r * rowH + 6;
      CreateTxt("T3_L1", baseX + 14, y + rowH / 2, "Hạn mức lỗ Ngày | Tuần | Tháng (%):", clrWhite, true);
      CreateEditBox("Ed_MaxDay",   col3_1, y + 2, smallW, ctlH, DoubleToString(g_maxDailyLossPct, 1),   g_riskBreached);
      CreateEditBox("Ed_MaxWeek",  col3_2, y + 2, smallW, ctlH, DoubleToString(g_maxWeeklyLossPct, 1),  g_riskBreached);
      CreateEditBox("Ed_MaxMonth", col3_3, y + 2, smallW, ctlH, DoubleToString(g_maxMonthlyLossPct, 1), g_riskBreached);
      CreateBtn("Btn_RiskGuard", colBtn, y + 2, btnW, ctlH,
                g_riskBreached ? "ĐANG KHÓA CỨNG" : (g_enRiskGuard ? "BẢO VỆ: BẬT" : "BẢO VỆ: TẮT"),
                g_riskBreached ? C_BTN_LOCK : (g_enRiskGuard ? C_BTN_ON : C_BTN_OFF), clrWhite);

      r = 1; y = yContent + r * rowH + 6;
      CreateTxt("T3_ProgD", baseX + 14,  y + rowH / 2, "Ngày: [░░░░░░░░░░] 0.0%",  clrLime, true);
      CreateTxt("T3_ProgW", baseX + 195, y + rowH / 2, "Tuần: [░░░░░░░░░░] 0.0%",  clrLime, true);
      CreateTxt("T3_ProgM", baseX + 375, y + rowH / 2, "Tháng: [░░░░░░░░░░] 0.0%", clrLime, true);

      r = 2; y = yContent + r * rowH + 6;
      CreateTxt("T3_L2", baseX + 14, y + rowH / 2, "Vốn tính Risk ($):", clrWhite, false);
      CreateEditBox("Ed_CustomEq", colEdit1, y + 2, editW * 2 + 8, ctlH, DoubleToString(g_customEquity, 0));
      CreateBtn("Btn_GetRealEq", colBtn, y + 2, btnW, ctlH, g_useLiveEquity ? "VỐN LIVE" : "VỐN TÙY CHỈNH", C_BTN_MODE, clrWhite);

      r = 3; y = yContent + r * rowH + 6;
      CreateTxt("T3_L3", baseX + 14, y + rowH / 2, "Phút cấm (Trước | Sau giờ tin):", clrWhite, false);
      CreateEditBox("Ed_MinBef", colEdit1, y + 2, editW, ctlH, IntegerToString(g_minBeforeNews));
      CreateEditBox("Ed_MinAft", colEdit2, y + 2, editW, ctlH, IntegerToString(g_minAfterNews));
      CreateBtn("Btn_News", colBtn, y + 2, btnW, ctlH,
                g_enNewsFilter ? "LỌC TIN: BẬT" : "LỌC TIN: TẮT",
                g_enNewsFilter ? C_BTN_ON : C_BTN_OFF, clrWhite);

      r = 4; y = yContent + r * rowH + 6;
      int wSlotBtn = (int)MathRound(58 * s);
      int gapSlot  = (int)MathRound(4 * s);
      int xS1 = baseX + 12;
      int xS2 = xS1 + wSlotBtn + gapSlot;
      int xS3 = xS2 + wSlotBtn + gapSlot;

      CreateBtn("Btn_EnSlot1", xS1, y + 2, wSlotBtn, ctlH, "TIN 1", g_enSlot1 ? C_BTN_ON : C_BTN_OFF, clrWhite);
      CreateBtn("Btn_EnSlot2", xS2, y + 2, wSlotBtn, ctlH, "TIN 2", g_enSlot2 ? C_BTN_ON : C_BTN_OFF, clrWhite);
      CreateBtn("Btn_EnSlot3", xS3, y + 2, wSlotBtn, ctlH, "TIN 3", g_enSlot3 ? C_BTN_ON : C_BTN_OFF, clrWhite);

      CreateEditBox("Ed_Slot1", col3_1, y + 2, smallW, ctlH, g_newsSlot1, !g_enSlot1);
      CreateEditBox("Ed_Slot2", col3_2, y + 2, smallW, ctlH, g_newsSlot2, !g_enSlot2);
      CreateEditBox("Ed_Slot3", col3_3, y + 2, smallW, ctlH, g_newsSlot3, !g_enSlot3);
      CreateBtn("Btn_NewsTz", colBtn, y + 2, btnW, ctlH,
                (g_newsTz == TZ_LOCAL_PC) ? "GIỜ MÁY (PC)" : "GIỜ SERVER MT5", C_BTN_MODE, clrWhite);

      r = 5; y = yContent + r * rowH + 6;
      CreateTxt("T3_L5", baseX + 14, y + rowH / 2, "Hạ nhiệt (h) | Lãi phục hồi (%) | PIN:", clrAqua, true);
      CreateEditBox("Ed_Cooldown", col3_1, y + 2, smallW, ctlH, DoubleToString(g_cooldownHours, 1), g_riskBreached);
      CreateEditBox("Ed_RecTarg",  col3_2, y + 2, smallW, ctlH, DoubleToString(g_recoveryTargetPct, 1));
      CreateEditBox("Ed_PinCode",  col3_3, y + 2, smallW, ctlH, g_enteredPinStr);
      CreateBtn("Btn_PinUnlock", colBtn, y + 2, btnW, ctlH, "MỞ KHÓA PIN", C_BTN_LOCK, clrWhite);

      r = 6; y = yContent + r * rowH + 6;
      CreateTxt("T3_L6", baseX + 14, y + rowH / 2,
                StringFormat("Equity Protect (Cắt lỗ %.1f | Chốt lời %.1f):", InpEquityDrawdownPct, InpEquityProfitTargetVal), clrGold, true);
      CreateBtn("Btn_EqScope", colEdit2, y + 2, editW + 16, ctlH,
                g_equityScopeAccount ? "TOÀN TK" : "SYMBOL", C_BTN_MODE, clrWhite);
      CreateBtn("Btn_EqProtect", colBtn, y + 2, btnW, ctlH,
                g_equityLatched ? "MỞ KHÓA EQ" : (g_equityProtectOn ? "EQ PROTECT: ON" : "EQ PROTECT: OFF"),
                g_equityLatched ? C_BTN_LOCK : (g_equityProtectOn ? C_BTN_ON : C_BTN_OFF), clrWhite);
   }
   else if(g_activeTab == TAB_AUTOMATE)
   {
      int r = 0, y = yContent + r * rowH + 6;
      CreateTxt("TA_L1", baseX + 14, y + rowH / 2, "Chế độ Ẩn: TP Ảo & SL Ảo (+Backup Server):", clrGold, true);
      int halfB = (btnW + editW) / 2;
      CreateBtn("Btn_VirtualTP", colBtn - halfB - 4, y + 2, halfB, ctlH,
                g_virtualTPOn ? "TP ẢO: BẬT" : "TP ẢO: TẮT", g_virtualTPOn ? C_BTN_ON : C_BTN_OFF, clrWhite);
      CreateBtn("Btn_VirtualSL", colBtn + (btnW - halfB), y + 2, halfB, ctlH,
                g_virtualSLOn ? "SL ẢO: BẬT" : "SL ẢO: TẮT", g_virtualSLOn ? C_BTN_ON : C_BTN_OFF, clrWhite);

      r = 1; y = yContent + r * rowH + 6;
      CreateTxt("TA_L2", baseX + 14, y + rowH / 2, "Đồng bộ Lệnh Mobile / Ngoài (2 chiều):", clrAqua, true);
      int wM = (int)MathRound(76 * s);
      CreateBtn("Btn_External",       col3_1,              y + 2, wM, ctlH, g_manageExternalOn ? "NHẬN: ON" : "NHẬN: OFF", g_manageExternalOn ? C_BTN_ON : C_BTN_OFF, clrWhite);
      CreateBtn("Btn_ReduceExternal", col3_1 + wM + 4,     y + 2, wM, ctlH, g_reduceExternalOn ? "CẮT DƯ: ON" : "CẮT DƯ: OFF", g_reduceExternalOn ? C_BTN_ACT : C_BTN_OFF, clrWhite);
      CreateBtn("Btn_AddExternal",    col3_1 + (wM + 4)*2, y + 2, wM + 10, ctlH, g_addExternalOn ? "BỒI THIẾU: ON" : "BỒI THIẾU: OFF", g_addExternalOn ? C_BTN_BUY : C_BTN_OFF, clrWhite,
                "Tự động mở bồi thêm phần Lot còn thiếu khi vào lệnh thăm dò từ điện thoại (0.02 + 0.13 = 0.15 lot)");

      r = 2; y = yContent + r * rowH + 6;
      CreateTxt("TA_L3", baseX + 14, y + rowH / 2, "Tự gắn SL/TP cho lệnh Mobile thiếu SL:", clrWhite, false);
      CreateBtn("Btn_AttachExtSlTp", colBtn, y + 2, btnW, ctlH,
                g_attachExternalSlTpOn ? "GẮN SL NGOÀI: ON" : "GẮN SL NGOÀI: OFF",
                g_attachExternalSlTpOn ? C_BTN_ON : C_BTN_OFF, clrWhite);

      r = 3; y = yContent + r * rowH + 6;
      CreateTxt("TA_L4", baseX + 14, y + rowH / 2,
                StringFormat("Đóng cuối ngày (%s) & Lịch tuần (%s):", InpTimedFlattenServerTime, InpWeeklyScheduleTime), clrWhite, false);
      CreateBtn("Btn_TimeMgr", colBtn - halfB - 4, y + 2, halfB, ctlH,
                g_timeManagerOn ? "CUỐI NGÀY: ON" : "CUỐI NGÀY: OFF", g_timeManagerOn ? C_BTN_ON : C_BTN_OFF, clrWhite);
      CreateBtn("Btn_Weekly",  colBtn + (btnW - halfB), y + 2, halfB, ctlH,
                g_weeklyOn ? "LỊCH TUẦN: ON" : "LỊCH TUẦN: OFF", g_weeklyOn ? C_BTN_ON : C_BTN_OFF, clrWhite);

      r = 4; y = yContent + r * rowH + 6;
      CreateTxt("TA_L5", baseX + 14, y + rowH / 2, "Trailing Lệnh Chờ & Hủy Lệnh Chờ EA:", clrWhite, false);
      CreateBtn("Btn_PendingTrail",    colBtn - halfB - 4, y + 2, halfB, ctlH,
                g_pendingTrailOn ? "TRAIL CHỜ: ON" : "TRAIL CHỜ: OFF", g_pendingTrailOn ? C_BTN_ON : C_BTN_OFF, clrWhite);
      CreateBtn("Btn_CancelEaPending", colBtn + (btnW - halfB), y + 2, halfB, ctlH,
                "HỦY LỆNH CHỜ", C_BTN_ACT, clrWhite);

      r = 5; y = yContent + r * rowH + 6;
      CreateTxt("TA_L6", baseX + 14, y + rowH / 2, "Sổ 20 Lệnh Chờ Ảo & 5 Tác vụ Tuần:", clrLime, true);
      CreateBtn("Btn_OpenDrawerVBook", colEdit1, y + 2, panelW - (colEdit1 - baseX) - 12, ctlH,
                "MỞ SỔ LỆNH ẢO & 5 LỊCH TUẦN ▸", (g_drawerMode == DRAWER_POS_VIRTUAL_BOOK) ? C_BTN_ON : C_TAB_ACTIVE, clrWhite);

      r = 6; y = yContent + r * rowH + 6;
      CreateTxt("TA_L7", baseX + 14, y + rowH / 2, "Đóng nhóm nhanh Async trên Symbol:", clrWhite, true);
      int gx = baseX + (int)MathRound(285 * s), gw = (int)MathRound(58 * s), gg = (int)MathRound(4 * s);
      CreateBtn("Btn_GroupBuy",     gx,               y + 2, gw, ctlH, "ĐÓNG BUY",  C_BTN_BUY,  clrWhite);
      CreateBtn("Btn_GroupSell",    gx + (gw + gg),   y + 2, gw, ctlH, "ĐÓNG SELL", C_BTN_SELL, clrWhite);
      CreateBtn("Btn_GroupWinners", gx + 2*(gw + gg), y + 2, gw, ctlH, "ĐÓNG LỜI",  C_BTN_ON,   clrWhite);
      CreateBtn("Btn_GroupLosers",  gx + 3*(gw + gg), y + 2, gw, ctlH, "ĐÓNG LỖ",   C_BTN_LOCK, clrWhite);

      r = 7; y = yContent + r * rowH + 6;
      CreateTxt("TA_L8", baseX + 14, y + rowH / 2, "Chuyển Symbol & Tất toán Symbol:", clrAqua, true);
      CreateBtn("Btn_SymbolPrev",          baseX + (int)MathRound(250 * s), y + 2, (int)MathRound(28 * s),  ctlH, "◄", C_BTN_MODE, clrWhite);
      CreateBtn("Btn_SymbolNext",          baseX + (int)MathRound(282 * s), y + 2, (int)MathRound(28 * s),  ctlH, "►", C_BTN_MODE, clrWhite);
      CreateBtn("Btn_CloseSymbol",         baseX + (int)MathRound(314 * s), y + 2, (int)MathRound(108 * s), ctlH, "ĐÓNG SYMBOL",  C_BTN_ACT,  clrWhite);
      CreateBtn("Btn_DeletePendingSymbol", baseX + (int)MathRound(426 * s), y + 2, (int)MathRound(116 * s), ctlH, "XÓA LỆNH CHỜ", C_BTN_MODE, clrWhite);
   }
   else // TAB_SETTINGS
   {
      int r = 0, y = yContent + r * rowH + 6;
      CreateTxt("TS_L1", baseX + 14, y + rowH / 2, "Chủ đề bảng màu (Mù màu / Kinh điển):", clrWhite, true);
      CreateBtn("Btn_ThemeToggle", colBtn, y + 2, btnW, ctlH,
                (g_colorTheme == THEME_COLORBLIND_SAFE) ? "MÀU: XANH-CAM" : "MÀU: XANH-ĐỎ",
                C_BTN_BUY, clrWhite);

      r = 1; y = yContent + r * rowH + 6;
      CreateTxt("TS_L2", baseX + 14, y + rowH / 2, "Hiển thị Đường ATR Neo & Thước Sizer:", clrWhite, false);
      int halfS = (btnW + editW) / 2;
      CreateBtn("Btn_ShowPlot",  colBtn - halfS - 4,       y + 2, halfS, ctlH, g_showAtrPlot ? "ATR LINE: BẬT" : "ATR LINE: TẮT", g_showAtrPlot ? C_BTN_ON : C_BTN_OFF, clrWhite);
      CreateBtn("Btn_ShowSizer", colBtn + (btnW - halfS),  y + 2, halfS, ctlH, g_showSizer   ? "SIZER: BẬT"    : "SIZER: TẮT",    g_showSizer   ? C_BTN_ON : C_BTN_OFF, clrWhite);

      r = 2; y = yContent + r * rowH + 6;
      CreateTxt("TS_L3", baseX + 14, y + rowH / 2, "Phím tắt (23 phím) & Cảnh báo S/R:", clrGold, true);
      CreateBtn("Btn_Hotkeys", colBtn - halfS - 4,      y + 2, halfS, ctlH, g_hotkeysOn  ? "PHÍM TẮT: BẬT" : "PHÍM TẮT: TẮT", g_hotkeysOn  ? C_BTN_ON : C_BTN_OFF, clrWhite);
      CreateBtn("Btn_SR",      colBtn + (btnW - halfS), y + 2, halfS, ctlH, g_srAlertsOn ? "BÁO S/R: BẬT"  : "BÁO S/R: TẮT",  g_srAlertsOn ? C_BTN_ON : C_BTN_OFF, clrWhite);

      r = 3; y = yContent + r * rowH + 6;
      CreateTxt("TS_L4", baseX + 14, y + rowH / 2, "Chụp biểu đồ PNG & Gửi ảnh Telegram:", clrAqua, true);
      CreateBtn("Btn_Screenshot",   colBtn - halfS - 4,      y + 2, halfS, ctlH, "📸 CHỤP & GỬI", C_BTN_ACT, clrWhite);
      CreateBtn("Btn_Telegram",     colBtn + (btnW - halfS), y + 2, (int)MathRound(halfS * 0.48), ctlH, g_telegramOn ? "TG: ON" : "TG: OFF", g_telegramOn ? C_BTN_ON : C_BTN_OFF, clrWhite);
      CreateBtn("Btn_TelegramTest", colBtn + (btnW - halfS) + (int)MathRound(halfS * 0.48) + 3, y + 2, halfS - (int)MathRound(halfS * 0.48) - 3, ctlH, "TEST TG", C_BTN_MODE, clrWhite);

      r = 4; y = yContent + r * rowH + 6;
      CreateTxt("TS_L5", baseX + 14, y + rowH / 2, "Bảng 23 Phím tắt & Cầu nối STTS:", clrLime, true);
      CreateBtn("Btn_OpenDrawerHotkeyStts", colEdit1, y + 2, panelW - (colEdit1 - baseX) - 12, ctlH,
                "MỞ BẢNG 23 PHÍM TẮT & STTS BRIDGE ▸", (g_drawerMode == DRAWER_HOTKEY_STTS) ? C_BTN_ON : C_TAB_ACTIVE, clrWhite);

      r = 5; y = yContent + r * rowH + 6;
      CreateTxt("TS_L6", baseX + 14, y + rowH / 2, "Lưu / Nạp Profile & Ma trận (.tdp):", clrAqua, true);
      int profileW = (panelW - 34) / 2;
      CreateBtn("Btn_SaveProfile", baseX + 10,                y + 2, profileW, ctlH + 2, "💾 LƯU PROFILE (.TDP)", C_BTN_BUY,  clrWhite);
      CreateBtn("Btn_LoadProfile", baseX + 18 + profileW,     y + 2, profileW, ctlH + 2, "📂 NẠP PROFILE (.TDP)", C_BTN_MODE, clrWhite);
   }

   // --- 5. THANH THAO TÁC NHANH 6 NÚT Ở ĐÁY (QUICK ACTION DOCK) ---
   int yFoot = baseY + rowH * 17 + 8;
   int qW    = (panelW - 34) / 6;
   int qGap  = 4;
   bool confirmCloseAllPending = (g_lastCloseAllClickTime > 0 && (TimeLocal() - g_lastCloseAllClickTime) <= 3);
   CreateBtn("Btn_SyncSlTp", baseX + 6 + (qW + qGap) * 0, yFoot, qW, ctlH + 4, "SETUP/SYNC",   C_BTN_MODE, clrWhite, "Tạo lại Setup khi chờ lệnh hoặc Đồng bộ SL/TP khi đang có lệnh");
   CreateBtn("Btn_Buy",      baseX + 6 + (qW + qGap) * 1, yFoot, qW, ctlH + 4, "▲ BUY",        C_BTN_BUY,  clrWhite, "Gửi lệnh BUY theo kiểu lệnh và ngân sách rủi ro đang chọn");
   CreateBtn("Btn_Sell",     baseX + 6 + (qW + qGap) * 2, yFoot, qW, ctlH + 4, "▼ SELL",       C_BTN_SELL, clrWhite, "Gửi lệnh SELL theo kiểu lệnh và ngân sách rủi ro đang chọn");
   CreateBtn("Btn_NowBE",    baseX + 6 + (qW + qGap) * 3, yFoot, qW, ctlH + 4, "DỜI SL BE",    C_BTN_ACT,  clrWhite, "Dời ngay lập tức SL về điểm Hòa vốn (Common BE / Entry + Điểm cộng)");
   CreateBtn("Btn_Close50",  baseX + 6 + (qW + qGap) * 4, yFoot, qW, ctlH + 4, "ĐÓNG 50% LOT", C_BTN_ACT,  clrWhite, "Đóng ngay lập tức 50% khối lượng các vị thế trên Symbol này");
   CreateBtn("Btn_CloseAll", baseX + 6 + (qW + qGap) * 5, yFoot, qW, ctlH + 4,
             confirmCloseAllPending ? "BẤM LẠI XÁC NHẬN!" : "ĐÓNG TẤT CẢ",
             confirmCloseAllPending ? clrRed : C_BTN_LOCK, clrWhite,
             "Bấm 2 lần liên tiếp trong 3 giây để xác nhận Đóng Tất Cả lệnh");

   // --- 6. THANH THÔNG BÁO TỨC THÌ (LIVE TOAST BAR) ---
   int yToast = baseY + rowH * 18 + 14;
   CreateBox("ToastBg",  baseX + 6, yToast, panelW - 12, rowH, C_BG_HEADER, C_BORDER);
   CreateTxt("Toast_Txt", baseX + 14, yToast + rowH / 2,
             "• " + g_lastToastMsg + ((g_lastToastTime > 0) ? (" [" + TimeToString(g_lastToastTime, TIME_SECONDS) + "]") : ""),
             clrAqua, false, MathMax(8, InpFontSize - 1));

   // --- 7. KẾT XUẤT NGĂN KÉO PHỤ BÊN CẠNH (NẾU ĐANG MỞ) ---
   if(g_drawerMode != DRAWER_CLOSED)
   {
      long chartW = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int drawerX = (baseX + panelW + drawerW + 10 <= (int)chartW) ? (baseX + panelW + 4) : MathMax(4, baseX - drawerW - 4);
      BuildContextualDrawer(drawerX, baseY, drawerW, g_panelH, rowH, ctlH, s);
   }
}

//+------------------------------------------------------------------+
//| Cập nhật giá trị động trên HUD, Đồng hồ Nến & Thanh Tiến độ      |
//+------------------------------------------------------------------+
void UpdateHudAndTabValues(double dayPct, double weekPct, double monthPct,
                           int openCount, double totalOpenVol, double vwapEntry,
                           double repSL, double repTP, bool basketIsLong, long anchorId, datetime earliestOpenTime,
                           double currentR, double netFloatingPnl)
{
   // Cập nhật đồng hồ đếm ngược đóng nến & Spread trên Header (Kế thừa STTS)
   if(!g_isDraggingPanel && ObjectFind(0, PREFIX + "HdrTitle") >= 0)
   {
      datetime bar0 = iTime(_Symbol, _Period, 0);
      int pSec      = PeriodSeconds(_Period);
      int remSec    = (bar0 > 0 && pSec > 0) ? (int)MathMax(0, (long)(bar0 + pSec) - (long)TimeCurrent()) : 0;
      int mm        = remSec / 60;
      int ss        = remSec % 60;
      int spreadPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      string hdrTxt = StringFormat("TRADEDESK PRO v12  •  %s · %s  |  ⏱ %02d:%02d  |  Spd: %d đ",
                                   _Symbol, GetTfShortName(_Period), mm, ss, spreadPts);
      ObjectSetString(0, PREFIX + "HdrTitle", OBJPROP_TEXT, hdrTxt);
   }

   double slDist, slPts, recLot, dispVol, dispRiskCash, dispRiskPct, dispRewardCash, partLot, remLot;
   bool riskKnown = true;
   CalculateSizingAndActiveRules(openCount, totalOpenVol, vwapEntry, repSL, repTP, basketIsLong, anchorId, earliestOpenTime,
                                 slDist, slPts, recLot, dispVol, dispRiskCash, dispRiskPct, riskKnown, dispRewardCash, partLot, remLot);

   bool   algoOn = (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED));
   string tfName = GetTfShortName(g_resolvedAtrTf);

   string marginModeStr = ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
                          ? "Hedging" : "Netting";

   string stTxt = algoOn ? (openCount > 0 ? StringFormat("● QUẢN LÝ %d LỆNH (%s | %s)", openCount, tfName,
                                                         (g_mixedPositionFallback ? "TÁCH 2 CHIỀU" : (g_multiMode == MULTI_BASKET_VWAP ? "VWAP" : "RIÊNG")))
                                          : StringFormat("● SẴN SÀNG (%s | ATR:%s)", marginModeStr, tfName))
                         : "● CHƯA BẬT ALGO TRADING!";
   color stClr = algoOn ? ((g_inRecoveryMode && g_enHalfRiskRec) ? clrViolet : (openCount > 0 ? clrDeepSkyBlue : clrLime)) : clrYellow;

   if(g_riskBreached || g_manualForceLock || g_equityLatched)
   {
      stTxt = g_equityLatched ? "● EQUITY PROTECT: ĐANG KHÓA" : (g_manualForceLock ? "● ĐÃ KHÓA THỦ CÔNG" : ("● " + g_breachReason));
      stClr = clrRed;
   }
   else if(g_enNewsFilter && g_newsLockedState)
   {
      stTxt = "● CẤM TRADE (TRONG GIỜ TIN)";
      stClr = clrOrangeRed;
   }
   else if(g_enRiskGuard && !g_riskDataAvailable)
   {
      stTxt = "● CHỜ ĐỒNG BỘ LỊCH SỬ MT5";
      stClr = clrOrangeRed;
   }

   string hud1 = g_riskDataAvailable
                 ? StringFormat("%s | N:%+.1f%% T:%+.1f%% Th:%+.1f%%", stTxt, dayPct, weekPct, monthPct)
                 : StringFormat("%s | Dữ liệu kỳ đang đồng bộ...", stTxt);
   ObjectSetString(0, PREFIX + "Hud_Line1", OBJPROP_TEXT, hud1);
   ObjectSetInteger(0, PREFIX + "Hud_Line1", OBJPROP_COLOR, stClr);

   // Cập nhật 3 thanh tiến độ màu trên Tab GUARD (nếu đang mở Tab GUARD)
   if(!g_isMinimized && g_activeTab == TAB_RISKNEWS)
   {
      double effD = MathMax(0.1, g_maxDailyLossPct   + g_pinExtraDayPct);
      double effW = MathMax(0.1, g_maxWeeklyLossPct  + g_pinExtraWeekPct);
      double effM = MathMax(0.1, g_maxMonthlyLossPct + g_pinExtraMonthPct);

      color cD = (dayPct   <= -effD * 0.8) ? clrRed : ((dayPct   <= -effD * 0.5) ? clrOrange : clrLime);
      color cW = (weekPct  <= -effW * 0.8) ? clrRed : ((weekPct  <= -effW * 0.5) ? clrOrange : clrLime);
      color cM = (monthPct <= -effM * 0.8) ? clrRed : ((monthPct <= -effM * 0.5) ? clrOrange : clrLime);

      if(ObjectFind(0, PREFIX + "T3_ProgD") >= 0)
      {
         ObjectSetString(0,  PREFIX + "T3_ProgD", OBJPROP_TEXT,  StringFormat("Ngày %s %.1f%%/%.1f%%",  BuildProgressBarText(dayPct, effD),   dayPct,   effD));
         ObjectSetInteger(0, PREFIX + "T3_ProgD", OBJPROP_COLOR, cD);
      }
      if(ObjectFind(0, PREFIX + "T3_ProgW") >= 0)
      {
         ObjectSetString(0,  PREFIX + "T3_ProgW", OBJPROP_TEXT,  StringFormat("Tuần %s %.1f%%/%.1f%%",  BuildProgressBarText(weekPct, effW),  weekPct,  effW));
         ObjectSetInteger(0, PREFIX + "T3_ProgW", OBJPROP_COLOR, cW);
      }
      if(ObjectFind(0, PREFIX + "T3_ProgM") >= 0)
      {
         ObjectSetString(0,  PREFIX + "T3_ProgM", OBJPROP_TEXT,  StringFormat("Tháng %s %.1f%%/%.1f%%", BuildProgressBarText(monthPct, effM), monthPct, effM));
         ObjectSetInteger(0, PREFIX + "T3_ProgM", OBJPROP_COLOR, cM);
      }
   }

   if(ObjectFind(0, PREFIX + "Btn_AtrTf") >= 0)
      ObjectSetString(0, PREFIX + "Btn_AtrTf", OBJPROP_TEXT, GetAtrTfBtnLabel());

   if(ObjectFind(0, PREFIX + "Btn_SyncSlTp") >= 0)
      ObjectSetString(0, PREFIX + "Btn_SyncSlTp", OBJPROP_TEXT, (openCount > 0) ? "SYNC SL/TP" : "TẠO SETUP");

   // Tự động trả nhãn nút ĐÓNG TẤT CẢ về bình thường nếu quá 3 giây không bấm xác nhận lần 2
   if(ObjectFind(0, PREFIX + "Btn_CloseAll") >= 0)
   {
      bool waitingSecondClick = (g_lastCloseAllClickTime > 0 && (TimeLocal() - g_lastCloseAllClickTime) <= 3);
      if(!waitingSecondClick && g_lastCloseAllClickTime > 0)
         g_lastCloseAllClickTime = 0;
      ObjectSetString(0,  PREFIX + "Btn_CloseAll", OBJPROP_TEXT,    waitingSecondClick ? "XÁC NHẬN?" : "ĐÓNG TẤT CẢ");
      ObjectSetInteger(0, PREFIX + "Btn_CloseAll", OBJPROP_BGCOLOR, waitingSecondClick ? clrRed      : C_BTN_LOCK);
   }

   double activeRisk = GetActiveRiskPercent();
   string hud2L = "", hud2R = "";
   if(openCount > 0)
   {
      if(g_mixedPositionFallback)
      {
         hud2L = StringFormat("HAI CHIỀU: hướng chính %.2f lot (SL %.0f đ)", dispVol, slPts);
         hud2R = StringFormat("Risk hướng chính: %.2f%% | TP1:%.2f / Còn:%.2f", dispRiskPct, partLot, remLot);
      }
      else
      {
         hud2L = riskKnown
                 ? StringFormat("Khớp:%.2fL (Gợi ý:%.2f) | SL:%.0fđ | -$%.1f", dispVol, recLot, slPts, dispRiskCash)
                 : StringFormat("Khớp:%.2fL (Gợi ý:%.2f) | SL:%.0fđ | Risk:?", dispVol, recLot, slPts);
         hud2R = riskKnown
                 ? StringFormat("Risk thực:%.2f%% (Thêm:%.2fL) | TP1:%.2f/Còn:%.2f", dispRiskPct, g_nextAddOnSuggestedLot, partLot, remLot)
                 : "Kiểm tra SL / dữ liệu broker; không giả định Risk = 0";
      }
   }
   else
   {
      if(g_enteredManualLot > 0.0)
      {
         hud2L = riskKnown
                 ? StringFormat("Gợi ý:%.2fL | Nhập:%.2fL (SL:%.0fđ) | -$%.1f", recLot, dispVol, slPts, dispRiskCash)
                 : "GỢI Ý: 0 lot | Risk danh mục / SL chưa xác định";
      }
      else
      {
         hud2L = riskKnown
                 ? StringFormat("GỢI Ý: %.2f Lot (SL: %.0f điểm) | -$%.1f", recLot, slPts, dispRiskCash)
                 : "GỢI Ý: 0 lot | Risk danh mục / SL chưa xác định";
      }
      hud2R = riskKnown
              ? (InpSplitSetupRiskAcrossOrders
                 ? StringFormat("Tổng %.2f%% [L1:%.2f | L2:%.2f | L3:%.2f]", activeRisk, g_leg1SuggestedLot, g_leg2SuggestedLot, g_leg3SuggestedLot)
                 : StringFormat("Risk mục tiêu: %.2f%% | TP1:%.2f / Còn:%.2f", activeRisk, partLot, remLot))
              : "Không thể bảo đảm mức Risk mục tiêu";
   }
   ObjectSetString(0,  PREFIX + "Hud_Line2L", OBJPROP_TEXT,  hud2L);
   ObjectSetInteger(0, PREFIX + "Hud_Line2L", OBJPROP_COLOR, (openCount > 0) ? clrLime : clrYellow);
   ObjectSetString(0,  PREFIX + "Hud_Line2R", OBJPROP_TEXT,  hud2R);
   ObjectSetInteger(0, PREFIX + "Hud_Line2R", OBJPROP_COLOR, clrAqua);

   string hud3L = "", hud3R = "";
   color  hud3Clr = clrGold;

   if(openCount > 0)
   {
      hud3L = StringFormat("Khớp:%s (KH:%s) | %+.2fR ($%.1f)",
                           DoubleToString(g_actualFillEntryPrice, _Digits),
                           DoubleToString(g_plannedEntryPrice, _Digits), currentR, netFloatingPnl);
      if(g_trailStyle == TRAIL_STYLE_MANUAL_SL)
         hud3R = "[SL TAY 100% - THỦ CÔNG]";
      else if(g_advTrailMode != ADV_TRAIL_OFF)
         hud3R = "[" + GetAdvTrailBtnLabel() + " ĐANG BẬT]";
      else if(g_trailStyle == TRAIL_STYLE_BE_FLOAT || !g_enTrail)
         hud3R = g_enPartial && partLot > 0.0
                 ? StringFormat("[CHỜ +%.1fR CẮT %.0f%% & DỜI BE]", g_partialRR, g_partialPct)
                 : "[THỦ CÔNG (CHỜ DỜI BE)]";
      else if(g_isTrailingArmedNow)
         hud3R = StringFormat("[ĐÃ BẬT TRAIL: %d T1 cứu | %d T2 cắt]", g_tier1SavedCount, g_tier2HalfCutCount);
      else if(g_enPartial && g_hardTpSuppressedForPartial)
         hud3R = StringFormat("[TP1 ẢO (GỠ HARD TP) | +%.1fR cắt %.0f%% & Trail]", g_partialRR, g_partialPct);
      else
         hud3R = StringFormat("[GIỮ SL | Chờ +%.1fR bật ATR Trail]", g_trailStartRR);

      hud3Clr = (g_enTrail && g_isTrailingArmedNow) ? clrLime : clrGold;
   }
   else
   {
      hud3L = StringFormat("Entry KH(%s): %s | ATR: %s",
                           tfName, DoubleToString(g_plannedEntryPrice, _Digits), DoubleToString(g_pineTrailingStop, _Digits));
      hud3R = g_virtualPendingActive
              ? (g_virtualPendingBuy ? "ĐANG CHỜ LỆNH ẢO BUY (XEM SỔ ẢO)" : "ĐANG CHỜ LỆNH ẢO SELL (XEM SỔ ẢO)")
              : g_newsStatusText;
      hud3Clr = g_virtualPendingActive ? clrGold : (g_newsLockedState ? clrRed : clrAqua);
   }

   ObjectSetString(0,  PREFIX + "Hud_Line3L", OBJPROP_TEXT,  hud3L);
   ObjectSetInteger(0, PREFIX + "Hud_Line3L", OBJPROP_COLOR, hud3Clr);
   ObjectSetString(0,  PREFIX + "Hud_Line3R", OBJPROP_TEXT,  hud3R);
   ObjectSetInteger(0, PREFIX + "Hud_Line3R", OBJPROP_COLOR, hud3Clr);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Bộ xử lý 23 Phím tắt (Có khóa chống xung đột khi đang gõ ô Edit) |
//+------------------------------------------------------------------+
bool HotkeyMatches(int keyCode, string configured, bool shiftDown)
{
   bool wantsShift = (StringFind(configured, "Shift+") == 0);
   if(wantsShift)
      configured = StringSubstr(configured, 6);
   if(wantsShift != shiftDown || StringLen(configured) != 1)
      return false;
   if(configured == "[") return (keyCode == 91 || keyCode == 219);
   if(configured == "]") return (keyCode == 93 || keyCode == 221);
   int wanted = (int)StringGetCharacter(configured, 0);
   if(wanted  >= 97 && wanted  <= 122) wanted  -= 32;
   if(keyCode >= 97 && keyCode <= 122) keyCode -= 32;
   return (keyCode == wanted);
}

bool ConfirmHotkeyTrade(string action)
{
   if(!InpConfirmHotkeyTrades)
      return true;
   int answer = MessageBox(StringFormat("Xác nhận thực thi phím tắt [%s] trên %s?", action, _Symbol),
                           "TuanProtrade - Hotkey Confirmation", MB_YESNO | MB_ICONQUESTION);
   return (answer == IDYES);
}

void HandleTradeDeskHotkey(int keyCode, bool shiftDown)
{
   // KHÓA CHỐNG XUNG ĐỘT: Tuyệt đối không chạy phím tắt khi con trỏ đang gõ trong ô OBJ_EDIT
   if(g_isEditingTextField || g_accountSwitchHold)
      return;

   if(HotkeyMatches(keyCode, InpHotkeyBuy, shiftDown))
   { if(ConfirmHotkeyTrade("VÀO LỆNH BUY")) PlaceManualOrder(true); return; }

   if(HotkeyMatches(keyCode, InpHotkeySell, shiftDown))
   { if(ConfirmHotkeyTrade("VÀO LỆNH SELL")) PlaceManualOrder(false); return; }

   if(HotkeyMatches(keyCode, InpHotkeyOCO, shiftDown))
   { if(ConfirmHotkeyTrade("ĐẶT CẶP OCO")) PlaceOcoBracket(); return; }

   if(HotkeyMatches(keyCode, InpHotkeyDeletePending, shiftDown))
   { CancelTradeDeskPending(); return; }

   if(HotkeyMatches(keyCode, InpHotkeyCloseAll, shiftDown))
   { if(ConfirmHotkeyTrade("ĐÓNG TẤT CẢ SYMBOL")) CloseAllTradesAndOrders("Phím tắt đóng Symbol", false); return; }

   if(HotkeyMatches(keyCode, InpHotkeyCloseWinners, shiftDown))
   { ClosePositionsByFilter(true, false, -1, false); return; }

   if(HotkeyMatches(keyCode, InpHotkeyCloseLosers, shiftDown))
   { ClosePositionsByFilter(false, true, -1, false); return; }

   if(HotkeyMatches(keyCode, InpHotkeyCloseBuy, shiftDown))
   { ClosePositionsByFilter(false, false, POSITION_TYPE_BUY, false); return; }

   if(HotkeyMatches(keyCode, InpHotkeyCloseSell, shiftDown))
   { ClosePositionsByFilter(false, false, POSITION_TYPE_SELL, false); return; }

   if(HotkeyMatches(keyCode, InpHotkeyNextSymbol, shiftDown))
   { SwitchChartSymbol(1); return; }

   if(HotkeyMatches(keyCode, InpHotkeyPreviousSymbol, shiftDown))
   { SwitchChartSymbol(-1); return; }

   if(HotkeyMatches(keyCode, InpHotkeyPendingOrder, shiftDown))
   {
      g_entryMode = (g_entryMode + 1) % 6;
      RebuildCleanPanel(false);
      SetToastStatus("Đổi kiểu lệnh: " + GetEntryModeBtnLabel());
      return;
   }

   if(HotkeyMatches(keyCode, InpHotkeyChangeDirection, shiftDown))
   {
      g_tradeSide = (g_tradeSide == SIDE_LONG) ? SIDE_SHORT : SIDE_LONG;
      RebuildCleanPanel(false);
      ProcessCoreLogic();
      return;
   }

   if(HotkeyMatches(keyCode, InpHotkeyTogglePanel, shiftDown))
   {
      g_isMinimized = !g_isMinimized;
      RebuildCleanPanel(true);
      ProcessCoreLogic();
      return;
   }

   if(HotkeyMatches(keyCode, InpHotkeyAutoAdjust, shiftDown))
   {
      g_autoSlTp = !g_autoSlTp;
      RebuildCleanPanel(false);
      SetToastStatus(g_autoSlTp ? "Tự gắn SL/TP: BẬT" : "Tự gắn SL/TP: TẮT");
      return;
   }

   if(HotkeyMatches(keyCode, InpHotkeyDrawBuy, shiftDown))
   {
      g_tradeSide = SIDE_LONG;
      g_slMode    = SL_MODE_DRAG;
      g_showSizer = true;
      RebuildCleanPanel(false);
      ProcessCoreLogic();
      return;
   }

   if(HotkeyMatches(keyCode, InpHotkeyDrawSell, shiftDown))
   {
      g_tradeSide = SIDE_SHORT;
      g_slMode    = SL_MODE_DRAG;
      g_showSizer = true;
      RebuildCleanPanel(false);
      ProcessCoreLogic();
      return;
   }

   if(HotkeyMatches(keyCode, InpHotkeyPinSL, shiftDown) ||
      HotkeyMatches(keyCode, InpHotkeyPinTP, shiftDown) ||
      HotkeyMatches(keyCode, InpHotkeyPinAll, shiftDown))
   {
      if(g_sizerEntryPrice > 0.0 && g_sizerSlPrice > 0.0)
      {
         g_pinSizerEntry = true;
         g_pinnedSlDist  = MathAbs(g_sizerEntryPrice - g_sizerSlPrice);
         SetToastStatus("Đã ghim cố định khoảng cách Entry/SL/TP");
         ProcessCoreLogic();
      }
      return;
   }

   if(HotkeyMatches(keyCode, InpHotkeyRiskReward, shiftDown))
   {
      Alert("TuanProtrade: Tỷ lệ R:R mục tiêu hiện tại là 1:", DoubleToString(g_targetRR, 2));
      return;
   }

   if(HotkeyMatches(keyCode, InpHotkeyClosePartial, shiftDown))
   {
      string execSym = GetExecutionSymbol();
      for(int j = PositionsTotal() - 1; j >= 0; j--)
      {
         ulong t = PositionGetTicket(j);
         if(t > 0 && (PositionGetString(POSITION_SYMBOL) == _Symbol || PositionGetString(POSITION_SYMBOL) == execSym))
            ClosePositionPartiallyByTicket(t, FloorLotStep(PositionGetDouble(POSITION_VOLUME) * 0.5));
      }
      return;
   }

   if(HotkeyMatches(keyCode, InpHotkeyBreakEven, shiftDown))
   {
      string execSym = GetExecutionSymbol();
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         string s = PositionGetString(POSITION_SYMBOL);
         if(s != _Symbol && s != execSym) continue;
         bool   isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
         double target = (g_enCommonBe && g_commonBePrice > 0.0)
                         ? g_commonBePrice
                         : NormalizePriceToTickSize(execSym, entry + (isBuy ? 1.0 : -1.0) * MathMax(0, g_bePoints) * _Point);
         ModifyPositionWithConfirmation(ticket, target, PositionGetDouble(POSITION_TP));
      }
      SetToastStatus("Đã dời SL về Hòa vốn (BE)");
      return;
   }
}

// ============================================================================
// CÁC HÀM SỰ KIỆN CHUẨN CỦA METATRADER 5 (ONINIT, ONDEINIT, ONTICK, ONEVENT)
// ============================================================================

int OnInit()
{
   Print("TuanProtrade v1.00 | Risk Guard + Equity Flatten retry + OCO half-risk | mode: conservative synchronous liquidation.");
   ObjectsDeleteAll(0, "EAPRO");
   ObjectsDeleteAll(0, "EAP31");
   ObjectsDeleteAll(0, "EAP40");
   ObjectsDeleteAll(0, "EAP50");
   ObjectsDeleteAll(0, "EAP51");
   ObjectsDeleteAll(0, "EAP60");
   ObjectsDeleteAll(0, "EAP61");
   ObjectsDeleteAll(0, "EAP62");
   ObjectsDeleteAll(0, "EAP70");
   ObjectsDeleteAll(0, "EAP71");
   ObjectsDeleteAll(0, "EAP72");
   ObjectsDeleteAll(0, "EAP73");
   ObjectsDeleteAll(0, "EAP74");
   ObjectsDeleteAll(0, "EAP75");
   ObjectsDeleteAll(0, "EAP76");
   ObjectsDeleteAll(0, "EAP77");
   ObjectsDeleteAll(0, "EAP78");
   ObjectsDeleteAll(0, "EAP79");
   ObjectsDeleteAll(0, "EAP80");
   ObjectsDeleteAll(0, "EAP81");
   ObjectsDeleteAll(0, "PSIZER");
   ObjectsDeleteAll(0, PREFIX);
   ObjectsDeleteAll(0, VIS_PREFIX);
   ObjectsDeleteAll(0, DRAG_PREFIX);
   ObjectsDeleteAll(0, JRN_PREFIX);

   if(UninitializeReason() != REASON_CHARTCHANGE)
      InitParamsFromInputs();

   g_initAccountLogin = AccountInfoInteger(ACCOUNT_LOGIN);
   g_initServerHash   = GetCurrentServerHash();

   string execSym = GetExecutionSymbol();
   trade.SetExpertMagicNumber((ulong)InpTradeMagicNumber);
   trade.SetDeviationInPoints((ulong)MathMax(0, InpMaxDeviationPoints));
   trade.SetTypeFillingBySymbol(execSym);

   string savedLoginKey  = AccountContextGVKey("LOGIN");
   string savedServerKey = AccountContextGVKey("SERVER");
   g_accountSwitchHold   = false;
   if(GlobalVariableCheck(savedLoginKey) && GlobalVariableCheck(savedServerKey))
   {
      long previousLogin      = (long)GlobalVariableGet(savedLoginKey);
      int  previousServerHash = (int)GlobalVariableGet(savedServerKey);
      g_accountSwitchHold     = (previousLogin != g_initAccountLogin || previousServerHash != g_initServerHash);
   }
   else if(PositionsTotal() > 0 || OrdersTotal() > 0)
   {
      g_accountSwitchHold = true; // Khi gắn EA lần đầu lên tài khoản đang có lệnh sống, yêu cầu người dùng bấm xác nhận
   }
   g_accountHoldRiskDataReady = false;

   LoadLockStateFromGV();
   CheckEquityProtect();
   LoadVirtualPending();

   ChartSetInteger(0, CHART_SHIFT, true);
   if(ChartGetDouble(0, CHART_SHIFT_SIZE) < 24.0)
      ChartSetDouble(0, CHART_SHIFT_SIZE, 26.0);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   RebuildCleanPanel(true);
   ProcessCoreLogic();
   EventSetMillisecondTimer(250);
   TelegramStartupReport();   // [v12.1.1]
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(g_initAccountLogin > 0)
   {
      GlobalVariableSet(AccountContextGVKey("LOGIN"),  (double)g_initAccountLogin);
      GlobalVariableSet(AccountContextGVKey("SERVER"), (double)g_initServerHash);
   }
   EventKillTimer();
   if(g_advTrailHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_advTrailHandle);
      g_advTrailHandle = INVALID_HANDLE;
   }
   if(g_sttsIndicatorHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_sttsIndicatorHandle);
      g_sttsIndicatorHandle = INVALID_HANDLE;
   }
   ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
   if(reason != REASON_CHARTCHANGE)
   {
      ObjectsDeleteAll(0, PREFIX);
      ObjectsDeleteAll(0, VIS_PREFIX);
      ObjectsDeleteAll(0, DRAG_PREFIX);
      ObjectsDeleteAll(0, JRN_PREFIX);
   }
   ChartRedraw(0);
}

void OnTick()
{
   ProcessFailedOcoCleanup();
   CheckEquityProtect();
   CheckScheduledFlatten();
   CheckSupportResistanceBreakout();
   CheckExternalSignalBridge();
   ProcessCoreLogic();
   ProcessVirtualPending();
   ProcessVirtualStops();
   ProcessVirtualTakeProfits();
   ProcessPendingOrderTrailing();
}

void OnTimer()
{
   ProcessFailedOcoCleanup();
   CheckEquityProtect();
   CheckScheduledFlatten();
   ProcessWeeklySchedule();
   ProcessAdvancedTrailing();
   CheckAccountRiskWarnings();   // [v12.1]
   TouchCriticalGlobals();       // [v12.1]
   ProcessTradeDeskNotificationQueue();
   ProcessCoreLogic();
   ProcessVirtualPending();
   ProcessVirtualStops();
   ProcessVirtualTakeProfits();
   ProcessPendingOrderTrailing();
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_KEYDOWN && g_hotkeysOn)
   {
      int keyFlags = (int)StringToInteger(sparam);
      HandleTradeDeskHotkey((int)lparam, (keyFlags & 4) != 0);
      return;
   }

   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int  mouseX    = (int)lparam;
      int  mouseY    = (int)dparam;
      uint mouseFlag = (uint)StringToInteger(sparam);
      bool leftDown  = ((mouseFlag & 1) == 1);

      if(leftDown && !g_prevMouseLeftDown)
      {
         int dragZoneRight = g_panelX + g_panelW - 165;
         if(mouseX >= g_panelX && mouseX <= dragZoneRight &&
            mouseY >= g_panelY && mouseY <= g_panelY + g_headerH)
         {
            g_isDraggingPanel = true;
            g_dragOffsetX     = mouseX - g_panelX;
            g_dragOffsetY     = mouseY - g_panelY;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
            RebuildCleanPanel(false);
            ChartRedraw(0);
         }
      }
      else if(leftDown && g_isDraggingPanel)
      {
         int newX = mouseX - g_dragOffsetX;
         int newY = mouseY - g_dragOffsetY;
         if(MathAbs(newX - g_panelX) >= 2 || MathAbs(newY - g_panelY) >= 2)
         {
            g_panelX = newX;
            g_panelY = newY;
            ClampPanelCoordinates();
            RebuildCleanPanel(false);
            ChartRedraw(0);
         }
      }
      else if(!leftDown && g_isDraggingPanel)
      {
         g_isDraggingPanel = false;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
         RebuildCleanPanel(false);
         ChartRedraw(0);
      }

      g_prevMouseLeftDown = leftDown;
      return;
   }

   if(g_accountSwitchHold)
   {
      if(id == CHARTEVENT_OBJECT_CLICK)
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         if(sparam == PREFIX + "Btn_ForceLock")
         {
            long activeLogin      = AccountInfoInteger(ACCOUNT_LOGIN);
            int  activeServerHash = GetCurrentServerHash();
            if(activeLogin != g_initAccountLogin || activeServerHash != g_initServerHash)
               Alert("Tài khoản/server vừa thay đổi thêm lần nữa. EA tiếp tục tạm dừng; hãy chờ khởi tạo lại.");
            else if(!g_accountHoldRiskDataReady || !g_riskDataAvailable)
               Alert("Lịch sử Risk Guard chưa tải xong. EA vẫn tạm dừng; hãy chờ MT5 đồng bộ rồi xác nhận lại.");
            else
            {
               g_accountSwitchHold = false;
               SetToastStatus("Đã xác nhận tài khoản! Hệ thống hoạt động.");
               RebuildCleanPanel(true);
               ProcessCoreLogic();
            }
         }
         else
         {
            static datetime s_lastHoldAlert = 0;   // [v12.1.1] chống spam popup mỗi lần click
            if(s_lastHoldAlert == 0 || TimeLocal() - s_lastHoldAlert >= 15)
            {
               s_lastHoldAlert = TimeLocal();
               Alert("EA đang tạm dừng để xác nhận tài khoản/lệnh hiện tại. Hãy kiểm tra vị thế rồi bấm nút XÁC NHẬN TK (khung HUD phía trên cùng bảng, góc phải) để tiếp tục.");
            }
         }
      }
      return;
   }

   if(id == CHARTEVENT_CHART_CHANGE)
   {
      ClampPanelCoordinates();
      RebuildCleanPanel(false);
      ProcessCoreLogic();
      return;
   }

   // --- XỬ LÝ KÉO THẢ CÁC ĐƯỜNG TRÊN BIỂU ĐỒ (SIZER, STOPLIMIT, V-SL, V-TP, V-PENDING) ---
   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      string execSym = GetExecutionSymbol();
      if(sparam == DRAG_PREFIX + "ENTRY")
      {
         g_slMode           = SL_MODE_DRAG;
         g_pinSizerEntry    = true;
         g_sizerEntryPrice  = NormalizePriceToTickSize(execSym, ObjectGetDouble(0, sparam, OBJPROP_PRICE, 0));
         RebuildCleanPanel(false);
         ProcessCoreLogic();
      }
      else if(sparam == DRAG_PREFIX + "SL")
      {
         g_slMode           = SL_MODE_DRAG;
         g_pinSizerEntry    = true;
         g_sizerSlPrice     = NormalizePriceToTickSize(execSym, ObjectGetDouble(0, sparam, OBJPROP_PRICE, 0));
         g_manualSlPts      = (int)MathRound(MathAbs(g_sizerEntryPrice - g_sizerSlPrice) / _Point);
         if(ObjectFind(0, PREFIX + "Ed_ManSlPts") >= 0)
            ObjectSetString(0, PREFIX + "Ed_ManSlPts", OBJPROP_TEXT, IntegerToString(g_manualSlPts));
         RebuildCleanPanel(false);
         ProcessCoreLogic();
      }
      else if(sparam == DRAG_PREFIX + "TP")
      {
         g_slMode           = SL_MODE_DRAG;
         g_pinSizerEntry    = true;
         g_sizerTpPrice     = NormalizePriceToTickSize(execSym, ObjectGetDouble(0, sparam, OBJPROP_PRICE, 0));
         double slDist      = MathAbs(g_sizerEntryPrice - g_sizerSlPrice);
         if(slDist > 0.0)
            g_targetRR = MathAbs(g_sizerTpPrice - g_sizerEntryPrice) / slDist;
         if(ObjectFind(0, PREFIX + "Ed_RR") >= 0)
            ObjectSetString(0, PREFIX + "Ed_RR", OBJPROP_TEXT, DoubleToString(g_targetRR, 2));
         RebuildCleanPanel(false);
         ProcessCoreLogic();
      }
      else if(sparam == DRAG_PREFIX + "STOPLIMIT")
      {
         g_sizerStopLimitPrice = NormalizePriceToTickSize(execSym, ObjectGetDouble(0, sparam, OBJPROP_PRICE, 0));
         g_stopLimitOffsetPts  = (int)MathRound(MathAbs(g_sizerEntryPrice - g_sizerStopLimitPrice) / _Point);
         if(ObjectFind(0, PREFIX + "Ed_StopLimPts") >= 0)
            ObjectSetString(0, PREFIX + "Ed_StopLimPts", OBJPROP_TEXT, IntegerToString(g_stopLimitOffsetPts));
         RebuildCleanPanel(false);
         ProcessCoreLogic();
      }
      else if(StringFind(sparam, VIS_PREFIX + "VSL_") == 0)
      {
         long pid = (long)StringToInteger(StringSubstr(sparam, StringLen(VIS_PREFIX + "VSL_")));
         double newVsl = NormalizePriceToTickSize(execSym, ObjectGetDouble(0, sparam, OBJPROP_PRICE, 0));
         if(pid > 0 && newVsl > 0.0)
         {
            GlobalVariableSet(VirtualSLPositionKey(pid), newVsl);
            SetToastStatus(StringFormat("Đã dời V-SL #%I64d -> %s", pid, DoubleToString(newVsl, _Digits)));
            ProcessCoreLogic();
         }
      }
      else if(StringFind(sparam, VIS_PREFIX + "VTP_") == 0)
      {
         long pid = (long)StringToInteger(StringSubstr(sparam, StringLen(VIS_PREFIX + "VTP_")));
         double newVtp = NormalizePriceToTickSize(execSym, ObjectGetDouble(0, sparam, OBJPROP_PRICE, 0));
         if(pid > 0 && newVtp > 0.0)
         {
            GlobalVariableSet(VirtualTPPositionKey(pid), newVtp);
            SetToastStatus(StringFormat("Đã dời V-TP #%I64d -> %s", pid, DoubleToString(newVtp, _Digits)));
            ProcessCoreLogic();
         }
      }
      else if(StringFind(sparam, VIS_PREFIX + "VPENDING_") == 0)
      {
         int slot = (int)StringToInteger(StringSubstr(sparam, StringLen(VIS_PREFIX + "VPENDING_")));
         double newPx = NormalizePriceToTickSize(execSym, ObjectGetDouble(0, sparam, OBJPROP_PRICE, 0));
         if(slot >= 0 && slot < 20 && g_virtualOrders[slot].state != VORD_INACTIVE && newPx > 0.0)
         {
            double shift = newPx - g_virtualOrders[slot].entryPrice;
            g_virtualOrders[slot].entryPrice     = newPx;
            g_virtualOrders[slot].stopLimitPrice = NormalizePriceToTickSize(execSym, g_virtualOrders[slot].stopLimitPrice + shift);
            g_virtualOrders[slot].slPrice        = NormalizePriceToTickSize(execSym, g_virtualOrders[slot].slPrice + shift);
            g_virtualOrders[slot].tpPrice        = NormalizePriceToTickSize(execSym, g_virtualOrders[slot].tpPrice + shift);
            SaveVirtualOrderBookToFile();
            SetToastStatus(StringFormat("Đã dời lệnh ảo #%d -> %s", slot + 1, DoubleToString(newPx, _Digits)));
            ProcessCoreLogic();
         }
      }
      return;
   }

   // --- XỬ LÝ KẾT THÚC NHẬP LIỆU Ô EDIT (CHARTEVENT_OBJECT_ENDEDIT) ---
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      g_isEditingTextField = false;
      g_focusedEditName    = "";

      string rawText = ObjectGetString(0, sparam, OBJPROP_TEXT);
      if(sparam == PREFIX + "Ed_PinCode")
      {
         g_enteredPinStr = rawText;
         RebuildCleanPanel(false);
         return;
      }

      string valStr = rawText;
      StringReplace(valStr, ",", ".");
      double valDbl = StringToDouble(valStr);
      int    valInt = (int)StringToInteger(valStr);

      if(sparam == PREFIX + "Ed_RiskPct" && valDbl > 0.0)
      {
         if(g_riskInputMode == RISK_INPUT_CASH) g_riskFixedCash = valDbl;
         else                                   g_riskPct       = valDbl;
      }
      if(sparam == PREFIX + "Ed_RR"           && valDbl > 0.0)  g_targetRR           = valDbl;
      if(sparam == PREFIX + "Ed_ManSlPts"     && valInt >= 1)   { g_manualSlPts      = valInt; g_slMode = SL_MODE_POINTS; }
      if(sparam == PREFIX + "Ed_PullbackPts"  && valInt >= 1)   g_pullbackPoints     = valInt;
      if(sparam == PREFIX + "Ed_StopLimPts"   && valInt >= 1)   g_stopLimitOffsetPts = valInt;
      if(sparam == PREFIX + "Ed_MaxChildLot"  && valDbl >= 0.0) g_maxLotPerOrder     = valDbl;
      if(sparam == PREFIX + "Ed_ManualLot"    && valDbl >= 0.0) g_enteredManualLot   = valDbl;
      if(sparam == PREFIX + "Ed_BufPts"       && valInt >= 0)   g_bufferPts          = valInt;
      if(sparam == PREFIX + "Ed_CommLot"      && valDbl >= 0.0) g_commPerLot         = valDbl;

      if(sparam == PREFIX + "Ed_AtrPer"    && valInt >= 1)   { g_atrLength = valInt; g_atrCacheValid = false; }
      if(sparam == PREFIX + "Ed_FirstMul"  && valDbl > 0.0)  { g_customValueForFirstDay = valDbl; g_atrCacheValid = false; }
      if(sparam == PREFIX + "Ed_AtrMul"    && valDbl > 0.0)  { g_atrMultiplier = valDbl; g_atrCacheValid = false; }
      if(sparam == PREFIX + "Ed_TrailRR"   && valDbl >= 0.0) { g_trailStartRR = valDbl; g_atrCacheValid = false; }
      if(sparam == PREFIX + "Ed_TierPct1R" && valDbl >= 5.0 && valDbl <= 90.0) { g_tierPctOf1R = valDbl; g_atrCacheValid = false; }
      if(sparam == PREFIX + "Ed_PartRR"    && valDbl > 0.0)  { g_partialRR  = valDbl; g_tpTiers[0].triggerVal = valDbl; }
      if(sparam == PREFIX + "Ed_PartPct"   && valDbl > 0.0 && valDbl < 100.0) { g_partialPct = valDbl; g_tpTiers[0].closePct = valDbl; }
      if(sparam == PREFIX + "Ed_BePts"     && valInt >= 0)   g_bePoints   = valInt;

      // Xử lý ô nhập trong Ngăn kéo 1 (Ma trận 10 TP / 10 SL)
      for(int t = 0; t < 10; t++)
      {
         string idxStr = IntegerToString(t + 1);
         if(sparam == PREFIX + "Ed_TpTrig_" + idxStr && valDbl > 0.0)
            g_tpTiers[t].triggerVal = valDbl;
         if(sparam == PREFIX + "Ed_TpPct_"  + idxStr && valDbl >= 1.0 && valDbl <= 100.0)
            g_tpTiers[t].closePct   = valDbl;
         if(sparam == PREFIX + "Ed_SlTrig_" + idxStr && valDbl > 0.0)
            g_slTiers[t].triggerVal = valDbl;
         if(sparam == PREFIX + "Ed_SlPct_"  + idxStr && valDbl >= 1.0 && valDbl <= 100.0)
            g_slTiers[t].closePct   = valDbl;
      }

      // Xử lý ô nhập trong Ngăn kéo 2 (4 Cấp BE & 4 Cấp Multi-Trail)
      for(int b = 0; b < 4; b++)
      {
         string bStr = IntegerToString(b + 1);
         if(sparam == PREFIX + "Ed_BeTrig_"  + bStr && valDbl > 0.0)  g_beStages[b].triggerVal         = valDbl;
         if(sparam == PREFIX + "Ed_BeLock_"  + bStr && valDbl >= 0.0) g_beStages[b].lockVal            = valDbl;
         if(sparam == PREFIX + "Ed_MTrGain_" + bStr && valDbl > 0.0)  g_multiTrailStages[b].triggerPts = valDbl;
         if(sparam == PREFIX + "Ed_MTrDist_" + bStr && valDbl > 0.0)  g_multiTrailStages[b].distPts    = valDbl;
         if(sparam == PREFIX + "Ed_MTrStep_" + bStr && valDbl > 0.0)  g_multiTrailStages[b].stepPts    = valDbl;
      }

      // Xử lý ô nhập trong Ngăn kéo 3 (5 Tác vụ Lịch Tuần)
      for(int w = 0; w < 5; w++)
      {
         string wStr = IntegerToString(w + 1);
         if(sparam == PREFIX + "Ed_WTaskTime_" + wStr && StringFind(rawText, ":") > 0)
            g_timeTasks[w].timeStr = rawText;
      }

      if(!g_riskBreached)
      {
         if(sparam == PREFIX + "Ed_MaxDay"   && valDbl > 0.0)  g_maxDailyLossPct   = valDbl;
         if(sparam == PREFIX + "Ed_MaxWeek"  && valDbl > 0.0)  g_maxWeeklyLossPct  = valDbl;
         if(sparam == PREFIX + "Ed_MaxMonth" && valDbl > 0.0)  g_maxMonthlyLossPct = valDbl;
         if(sparam == PREFIX + "Ed_Cooldown" && valDbl >= 0.0) g_cooldownHours     = valDbl;
      }
      else if(sparam == PREFIX + "Ed_MaxDay"   || sparam == PREFIX + "Ed_MaxWeek" ||
              sparam == PREFIX + "Ed_MaxMonth" || sparam == PREFIX + "Ed_Cooldown")
      {
         Alert("ĐANG KHÓA KỶ LUẬT! Không thể tự ý nới rộng hạn mức lỗ hoặc giảm giờ hạ nhiệt.");
      }

      if(sparam == PREFIX + "Ed_CustomEq" && valDbl > 0.0)
      {
         g_customEquity  = valDbl;
         g_useLiveEquity = false;
      }
      if(sparam == PREFIX + "Ed_MinBef" && valInt >= 0) g_minBeforeNews = valInt;
      if(sparam == PREFIX + "Ed_MinAft" && valInt >= 0) g_minAfterNews  = valInt;
      if(sparam == PREFIX + "Ed_Slot1") g_newsSlot1 = rawText;
      if(sparam == PREFIX + "Ed_Slot2") g_newsSlot2 = rawText;
      if(sparam == PREFIX + "Ed_Slot3") g_newsSlot3 = rawText;

      if(sparam == PREFIX + "Ed_Yr" || sparam == PREFIX + "Ed_Mo" || sparam == PREFIX + "Ed_Dy")
      {
         g_atrCacheValid = false;
         if(valInt <= 0)
         {
            g_autoSyncDate = true;
            SyncAnchorDateFields(g_resolvedAtrTf, 0);
         }
         else
         {
            g_autoSyncDate = false;
            if(sparam == PREFIX + "Ed_Yr" && valInt >= 1900 && valInt <= 2100) g_entryDateYear  = valInt;
            if(sparam == PREFIX + "Ed_Mo" && valInt >= 1    && valInt <= 12)   g_entryDateMonth = valInt;
            if(sparam == PREFIX + "Ed_Dy" && valInt >= 1    && valInt <= 31)   g_entryDateDay   = valInt;
         }
      }

      if(sparam == PREFIX + "Ed_RecTarg" && valDbl > 0.0)
         g_recoveryTargetPct = valDbl;

      if(sparam == PREFIX + "Ed_RR"     || sparam == PREFIX + "Ed_ManSlPts" ||
         sparam == PREFIX + "Ed_AtrPer" || sparam == PREFIX + "Ed_FirstMul" || sparam == PREFIX + "Ed_AtrMul" ||
         sparam == PREFIX + "Ed_Yr"     || sparam == PREFIX + "Ed_Mo"       || sparam == PREFIX + "Ed_Dy")
      {
         if(CountPositionsInScope(false) == 0)
            ResetStandbySetupLock(g_resolvedAtrTf);
      }

      RebuildCleanPanel(false);
      ProcessCoreLogic();
      return;
   }

   // --- XỬ LÝ SỰ KIỆN CLICK CHUỘT VÀO NÚT & Ô EDIT (CHARTEVENT_OBJECT_CLICK) ---
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      // Nếu người dùng nhấp vào ô OBJ_EDIT, bật cờ khóa phím tắt để gõ số/chữ an toàn
      if(ObjectGetInteger(0, sparam, OBJPROP_TYPE) == OBJ_EDIT)
      {
         g_isEditingTextField = true;
         g_focusedEditName    = sparam;
         return;
      }
      g_isEditingTextField = false;
      g_focusedEditName    = "";
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);

      // Chuyển Tab chính
      if(sparam == PREFIX + "Tab_Pos")      { g_activeTab = TAB_POSITION; RebuildCleanPanel(true); ProcessCoreLogic(); return; }
      if(sparam == PREFIX + "Tab_Trail")    { g_activeTab = TAB_TRAILING; RebuildCleanPanel(true); ProcessCoreLogic(); return; }
      if(sparam == PREFIX + "Tab_Risk")     { g_activeTab = TAB_RISKNEWS; RebuildCleanPanel(true); ProcessCoreLogic(); return; }
      if(sparam == PREFIX + "Tab_Auto")     { g_activeTab = TAB_AUTOMATE; RebuildCleanPanel(true); ProcessCoreLogic(); return; }
      if(sparam == PREFIX + "Tab_Settings") { g_activeTab = TAB_SETTINGS; RebuildCleanPanel(true); ProcessCoreLogic(); return; }

      // Điều khiển Ngăn kéo Cấu hình Phụ (Contextual Flyout Drawer)
      if(sparam == PREFIX + "Btn_DrwClose")
      { g_drawerMode = DRAWER_CLOSED; RebuildCleanPanel(true); ProcessCoreLogic(); return; }
      if(sparam == PREFIX + "Btn_DrawerToggle" || sparam == PREFIX + "Btn_OpenDrawerMatrix")
      { g_drawerMode = (g_drawerMode == DRAWER_PARTIAL_MATRIX) ? DRAWER_CLOSED : DRAWER_PARTIAL_MATRIX; RebuildCleanPanel(true); ProcessCoreLogic(); return; }
      if(sparam == PREFIX + "Btn_OpenDrawerBeTrail")
      { g_drawerMode = (g_drawerMode == DRAWER_BE_TRAIL_MATRIX) ? DRAWER_CLOSED : DRAWER_BE_TRAIL_MATRIX; RebuildCleanPanel(true); ProcessCoreLogic(); return; }
      if(sparam == PREFIX + "Btn_OpenDrawerVBook")
      { g_drawerMode = (g_drawerMode == DRAWER_POS_VIRTUAL_BOOK) ? DRAWER_CLOSED : DRAWER_POS_VIRTUAL_BOOK; RebuildCleanPanel(true); ProcessCoreLogic(); return; }
      if(sparam == PREFIX + "Btn_OpenDrawerHotkeyStts")
      { g_drawerMode = (g_drawerMode == DRAWER_HOTKEY_STTS) ? DRAWER_CLOSED : DRAWER_HOTKEY_STTS; RebuildCleanPanel(true); ProcessCoreLogic(); return; }

      // Các nút bên trong Ngăn kéo Phụ
      for(int t = 0; t < 10; t++)
      {
         string idxStr = IntegerToString(t + 1);
         if(sparam == PREFIX + "Btn_TpTierOn_" + idxStr)
         {
            g_tpTiers[t].enabled = !g_tpTiers[t].enabled;
            if(t == 0) g_enPartial = g_tpTiers[0].enabled;
            RebuildCleanPanel(false);
            return;
         }
         if(sparam == PREFIX + "Btn_SlTierOn_" + idxStr)
         {
            g_slTiers[t].enabled = !g_slTiers[t].enabled;
            if(g_slTiers[t].enabled) g_enPartialSL = true;
            RebuildCleanPanel(false);
            return;
         }
      }
      if(sparam == PREFIX + "Btn_TpUnitCycle")
      {
         ENUM_TRIGGER_UNIT nextU = (ENUM_TRIGGER_UNIT)(((int)g_tpTiers[0].triggerUnit + 1) % 4);
         for(int i = 0; i < 10; i++)
            g_tpTiers[i].triggerUnit = nextU;
         RebuildCleanPanel(false);
         return;
      }
      if(sparam == PREFIX + "Btn_PartialSlMaster")
      {
         g_enPartialSL = !g_enPartialSL;
         SetToastStatus(g_enPartialSL ? "Cắt lỗ từng phần 10 cấp: BẬT" : "Cắt lỗ từng phần 10 cấp: TẮT");
         RebuildCleanPanel(false);
         return;
      }

      for(int b = 0; b < 4; b++)
      {
         string bStr = IntegerToString(b + 1);
         if(sparam == PREFIX + "Btn_BeStgOn_" + bStr)
         { g_beStages[b].enabled = !g_beStages[b].enabled; RebuildCleanPanel(false); return; }
         if(sparam == PREFIX + "Btn_MTrOn_"   + bStr)
         { g_multiTrailStages[b].enabled = !g_multiTrailStages[b].enabled; RebuildCleanPanel(false); return; }
      }
      if(sparam == PREFIX + "Btn_CommonBeToggle")
      { g_enCommonBe = !g_enCommonBe; RebuildCleanPanel(false); ProcessCoreLogic(); return; }
      if(sparam == PREFIX + "Btn_LockProfitToggle")
      { g_enLock = !g_enLock; RebuildCleanPanel(false); ProcessCoreLogic(); return; }

      for(int w = 0; w < 5; w++)
      {
         string wStr = IntegerToString(w + 1);
         if(sparam == PREFIX + "Btn_WTaskOn_" + wStr)
         {
            g_timeTasks[w].enabled = !g_timeTasks[w].enabled;
            if(w == 0) g_weeklyOn = g_timeTasks[0].enabled;
            RebuildCleanPanel(false);
            return;
         }
         if(sparam == PREFIX + "Btn_WTaskAct_" + wStr)
         {
            g_timeTasks[w].action = (ENUM_WEEKLY_ACTION)(((int)g_timeTasks[w].action + 1) % 6);
            RebuildCleanPanel(false);
            return;
         }
      }

      if(sparam == PREFIX + "Btn_SttsMode")
      {
         g_sttsBridgeMode = (ENUM_STTS_BRIDGE_MODE)(((int)g_sttsBridgeMode + 1) % 3);
         SetToastStatus("Đã chuyển chế độ Cầu nối STTS");
         RebuildCleanPanel(false);
         return;
      }

      // Nút Thu gọn & Đổi góc
      if(sparam == PREFIX + "Btn_Min")
      {
         g_isMinimized = !g_isMinimized;
         RebuildCleanPanel(true);
         ProcessCoreLogic();
         return;
      }
      else if(sparam == PREFIX + "Btn_Area")
      {
         long chartW = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
         long chartH = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
         g_cornerPresetIdx = (g_cornerPresetIdx + 1) % 4;
         if(g_cornerPresetIdx == 0)      { g_panelX = 14;                         g_panelY = 82; }
         else if(g_cornerPresetIdx == 1) { g_panelX = (int)chartW - g_panelW - 14; g_panelY = 18; }
         else if(g_cornerPresetIdx == 2) { g_panelX = (int)chartW - g_panelW - 14; g_panelY = (int)chartH - g_panelH - 15; }
         else                            { g_panelX = 14;                         g_panelY = (int)chartH - g_panelH - 15; }
         ClampPanelCoordinates();
         RebuildCleanPanel(true);
         ProcessCoreLogic();
         return;
      }
      else if(sparam == PREFIX + "Btn_Buy")  { PlaceManualOrder(true);  return; }
      else if(sparam == PREFIX + "Btn_Sell") { PlaceManualOrder(false); return; }
      else if(sparam == PREFIX + "Btn_EntryMode")
      {
         g_entryMode = (g_entryMode + 1) % 6;
         SetToastStatus("Chọn kiểu vào lệnh: " + GetEntryModeBtnLabel());
      }
      else if(sparam == PREFIX + "Btn_OcoModeCycle")
      {
         g_ocoMode = (ENUM_OCO_MODE)(((int)g_ocoMode + 1) % 5);
         SetToastStatus("Chế độ OCO: " + GetOcoModeBtnLabel());
      }
      else if(sparam == PREFIX + "Btn_EntrySide")
      {
         g_tradeSide = (g_tradeSide == SIDE_LONG) ? SIDE_SHORT : SIDE_LONG;
         g_atrCacheValid = false;
         ProcessCoreLogic();
      }
      else if(sparam == PREFIX + "Btn_ArmVirtual")      { ArmOrCancelVirtualPending(); RebuildCleanPanel(false); return; }
      else if(sparam == PREFIX + "Btn_CreateOco")       { PlaceOcoBracket();           RebuildCleanPanel(false); return; }
      else if(sparam == PREFIX + "Btn_CancelEaPending") { CancelTradeDeskPending(); }
      else if(sparam == PREFIX + "Btn_Screenshot")      { CaptureChartScreenshot(false, "MANUAL"); }
      else if(sparam == PREFIX + "Btn_SaveProfile")     { SaveTradeDeskProfile(); RebuildCleanPanel(false); return; }
      else if(sparam == PREFIX + "Btn_LoadProfile")     { LoadTradeDeskProfile(); RebuildCleanPanel(false); ProcessCoreLogic(); return; }
      else if(sparam == PREFIX + "Btn_ThemeToggle")
      {
         g_colorTheme = (g_colorTheme == THEME_COLORBLIND_SAFE) ? THEME_CLASSIC_GREENRED : THEME_COLORBLIND_SAFE;
         ApplyColorThemePalette();
         g_atrCacheValid = false;
         RebuildCleanPanel(true);
         ProcessCoreLogic();
         return;
      }
      else if(sparam == PREFIX + "Btn_VirtualTP")
      {
         g_virtualTPOn = !g_virtualTPOn;
         SetToastStatus(g_virtualTPOn ? "TP Ảo: BẬT (Cần EA chạy)" : "TP Ảo: TẮT (Dùng TP Broker)");
      }
      else if(sparam == PREFIX + "Btn_VirtualSL")
      {
         g_virtualSLOn = !g_virtualSLOn;
         SetToastStatus(g_virtualSLOn ? StringFormat("SL Ảo: BẬT (SL Khẩn cấp Server %.2fx)", MathMax(1.05, InpEmergencySLMultiplier))
                                      : "SL Ảo: TẮT (Dùng SL Broker)");
      }
      else if(sparam == PREFIX + "Btn_Telegram")
      {
         g_telegramOn = !g_telegramOn;
         SetToastStatus(g_telegramOn ? "Telegram Bot: BẬT" : "Telegram Bot: TẮT");
      }
      else if(sparam == PREFIX + "Btn_TelegramTest")
      {
         if(!g_telegramOn)
            Alert("Hãy bật nút TG: ON trước khi gửi thử.");
         else
         {
            string shot = InpTelegramSendPhotoChart ? CaptureChartScreenshot(true, "TG_TEST") : "";
            QueueTradeDeskNotification("TuanProtrade Test Message | " + _Symbol + " | " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), true, shot);
            SetToastStatus("Đã xếp tin nhắn & ảnh biểu đồ vào hàng đợi Telegram!");
         }
      }
      else if(sparam == PREFIX + "Btn_RiskMode")
      {
         g_riskInputMode = (ENUM_RISK_INPUT_MODE)(((int)g_riskInputMode + 1) % 8);
         SetToastStatus("Cơ sở vốn: " + GetRiskInputModeText());
         RebuildCleanPanel(false);
         ProcessCoreLogic();
         return;
      }
      else if(sparam == PREFIX + "Btn_AdvancedTrail")
      {
         g_advTrailMode       = (ENUM_ADV_TRAIL_MODE)(((int)g_advTrailMode + 1) % 9);
         g_advTrailHandleMode = ADV_TRAIL_OFF;
         SetToastStatus("Kiểu Trailing: " + GetAdvTrailBtnLabel());
         RebuildCleanPanel(false);
         return;
      }
      else if(sparam == PREFIX + "Btn_Weekly")
      {
         g_weeklyOn = !g_weeklyOn;
         g_timeTasks[0].enabled = g_weeklyOn;
         SetToastStatus(g_weeklyOn ? "Lịch giao dịch tuần: BẬT" : "Lịch giao dịch tuần: TẮT");
         RebuildCleanPanel(false);
         return;
      }
      else if(sparam == PREFIX + "Btn_Hotkeys")
      {
         g_hotkeysOn = !g_hotkeysOn;
         SetToastStatus(g_hotkeysOn ? "Điều khiển Phím tắt: BẬT" : "Điều khiển Phím tắt: TẮT");
         RebuildCleanPanel(false);
         return;
      }
      else if(sparam == PREFIX + "Btn_SR")
      {
         g_srAlertsOn    = !g_srAlertsOn;
         g_previousSRBid = 0.0;
         g_previousSRAsk = 0.0;
         SetToastStatus(g_srAlertsOn ? "Cảnh báo Hỗ trợ/Kháng cự: BẬT" : "Cảnh báo S/R: TẮT");
         RebuildCleanPanel(false);
         return;
      }
      else if(sparam == PREFIX + "Btn_External")
      {
         g_manageExternalOn = !g_manageExternalOn;
         if(!g_manageExternalOn)
         {
            g_reduceExternalOn = false;
            g_addExternalOn    = false;
         }
         SetToastStatus(g_manageExternalOn ? "Nhận diện lệnh Mobile/Ngoài: BẬT" : "Nhận diện lệnh Mobile/Ngoài: TẮT");
         RebuildCleanPanel(false);
         return;
      }
      else if(sparam == PREFIX + "Btn_ReduceExternal")
      {
         g_reduceExternalOn = !g_reduceExternalOn;
         if(g_reduceExternalOn) g_manageExternalOn = true;
         SetToastStatus(g_reduceExternalOn ? "Tự cắt bớt Lot lệnh ngoài vượt Risk: BẬT" : "Tự cắt bớt Lot lệnh ngoài: TẮT");
         RebuildCleanPanel(false);
         return;
      }
      else if(sparam == PREFIX + "Btn_AddExternal")
      {
         g_addExternalOn = !g_addExternalOn;
         if(g_addExternalOn) g_manageExternalOn = true;
         SetToastStatus(g_addExternalOn ? "Tự bồi thêm Lot thiếu cho lệnh Mobile: BẬT" : "Tự bồi thêm Lot lệnh Mobile: TẮT");
         RebuildCleanPanel(false);
         return;
      }
      else if(sparam == PREFIX + "Btn_AttachExtSlTp")
      {
         g_attachExternalSlTpOn = !g_attachExternalSlTpOn;
         if(g_attachExternalSlTpOn) g_manageExternalOn = true;
         SetToastStatus(g_attachExternalSlTpOn ? "Tự gắn SL/TP cho lệnh Mobile: BẬT" : "Tự gắn SL/TP cho lệnh Mobile: TẮT");
         RebuildCleanPanel(false);
         return;
      }
      else if(sparam == PREFIX + "Btn_GroupBuy")     ClosePositionsByFilter(false, false, POSITION_TYPE_BUY,  false);
      else if(sparam == PREFIX + "Btn_GroupSell")    ClosePositionsByFilter(false, false, POSITION_TYPE_SELL, false);
      else if(sparam == PREFIX + "Btn_GroupWinners") ClosePositionsByFilter(true,  false, -1, false);
      else if(sparam == PREFIX + "Btn_GroupLosers")  ClosePositionsByFilter(false, true,  -1, false);
      else if(sparam == PREFIX + "Btn_SymbolPrev")   { SwitchChartSymbol(-1); return; }
      else if(sparam == PREFIX + "Btn_SymbolNext")   { SwitchChartSymbol(1);  return; }
      else if(sparam == PREFIX + "Btn_CloseSymbol")
      {
         string execSym = GetExecutionSymbol();
         ClosePositionsByFilter(false, false, -1, false);
         for(int i = OrdersTotal() - 1; i >= 0; i--)
         {
            ulong pt = OrderGetTicket(i);
            if(pt > 0 && (OrderGetString(ORDER_SYMBOL) == _Symbol || OrderGetString(ORDER_SYMBOL) == execSym))
               DeleteOrderWithConfirmation(pt);
         }
         if(g_virtualPendingActive)
            ClearVirtualPending("đóng Symbol theo thao tác người dùng");
      }
      else if(sparam == PREFIX + "Btn_DeletePendingSymbol")
      {
         string execSym = GetExecutionSymbol();
         int deleted = 0;
         for(int i = OrdersTotal() - 1; i >= 0; i--)
         {
            ulong pt = OrderGetTicket(i);
            if(pt > 0 && (OrderGetString(ORDER_SYMBOL) == _Symbol || OrderGetString(ORDER_SYMBOL) == execSym))
            {
               if(DeleteOrderWithConfirmation(pt))
                  deleted++;
            }
         }
         if(g_virtualPendingActive)
         {
            ClearVirtualPending("xóa lệnh chờ theo thao tác người dùng");
            deleted++;
         }
         SetToastStatus(StringFormat("Đã yêu cầu xóa %d lệnh chờ trên %s", deleted, _Symbol));
      }
      else if(sparam == PREFIX + "Btn_EqProtect")
      {
         if(g_equityLatched)
         {
            GlobalVariableSet(AccountScopedGV("TD_EQ_LOCK"), 0.0);
            GlobalVariableSet(AccountScopedGV("TD_EQ_PEAK"), AccountInfoDouble(ACCOUNT_EQUITY));
            g_equityLatched   = false;
            g_equityProtectOn = true;
            SetToastStatus("Đã mở khóa Equity Protect & đặt lại đỉnh Equity");
         }
         else
            g_equityProtectOn = !g_equityProtectOn;
      }
      else if(sparam == PREFIX + "Btn_TimeMgr")      g_timeManagerOn   = !g_timeManagerOn;
      else if(sparam == PREFIX + "Btn_PendingTrail") g_pendingTrailOn  = !g_pendingTrailOn;
      else if(sparam == PREFIX + "Btn_EqScope")      g_equityScopeAccount = !g_equityScopeAccount;
      else if(sparam == PREFIX + "Btn_ForceLock")
      {
         g_manualForceLock = !g_manualForceLock;
         SaveLockStateToGV();
         if(g_manualForceLock)
            CloseAllTradesAndOrders("Người dùng bấm nút KHÓA NGAY");
      }
      else if(sparam == PREFIX + "Btn_RiskGuard")
      {
         if(g_riskBreached)
            Alert("ĐANG KHÓA KỶ LUẬT! Không thể tắt Bảo vệ khi đang vi phạm.");
         else
            g_enRiskGuard = !g_enRiskGuard;
      }
      else if(sparam == PREFIX + "Btn_PinUnlock")
      {
         TryEmergencyPinUnlock();
         return;
      }
      else if(sparam == PREFIX + "Btn_SlMode")
      {
         g_slMode = (ENUM_SL_CALC_MODE)(((int)g_slMode + 1) % 5);
         ResetStandbySetupLock(_Period);
      }
      else if(sparam == PREFIX + "Btn_AtrTf")
      {
         g_atrTfMode     = (ENUM_ATR_TF_MODE)(((int)g_atrTfMode + 1) % 7);
         g_autoSyncDate  = true;
         g_atrCacheValid = false;
         ResetStandbySetupLock(_Period);
      }
      else if(sparam == PREFIX + "Btn_Journal")
      {
         g_showJournal = !g_showJournal;
      }
      else if(sparam == PREFIX + "Btn_VolRule")
      {
         g_volRule = (g_volRule == RULE_KEEP_DIST_CALC_CASH) ? RULE_SCALE_DIST_BY_VOL : RULE_KEEP_DIST_CALC_CASH;
      }
      else if(sparam == PREFIX + "Btn_MultiMode")
      {
         g_multiMode = (g_multiMode == MULTI_BASKET_VWAP) ? MULTI_INDIVIDUAL : MULTI_BASKET_VWAP;
      }
      else if(sparam == PREFIX + "Btn_SweepMode")
      {
         g_sweepMode     = (ENUM_SWEEP_PROTECTION)(((int)g_sweepMode + 1) % 3);
         g_atrCacheValid = false;
      }
      else if(sparam == PREFIX + "Btn_AtrSrc")
      {
         g_atrSource     = (g_atrSource == ATR_SRC_CLOSE_SWING) ? ATR_SRC_HIGH_LOW : ATR_SRC_CLOSE_SWING;
         g_atrCacheValid = false;
      }
      else if(sparam == PREFIX + "Btn_Trail")
      {
         g_trailStyle = (ENUM_TRAIL_STYLE)(((int)g_trailStyle + 1) % 3);
         ApplyTrailStyleFlags();
      }
      else if(sparam == PREFIX + "Btn_AutoSlTp")  g_autoSlTp    = !g_autoSlTp;
      else if(sparam == PREFIX + "Btn_ShowSizer") g_showSizer   = !g_showSizer;
      else if(sparam == PREFIX + "Btn_ShowPlot")  { g_showAtrPlot = !g_showAtrPlot; g_atrCacheValid = false; }
      else if(sparam == PREFIX + "Btn_Be")
      {
         // Xoay vòng đủ 4 trạng thái chuẩn đặc tả: TP1+BE -> TP1:Giữ SL -> Chỉ BE -> Tắt cả hai
         if(g_enPartial && g_enBe)        { g_enPartial = true;  g_enBe = false; }
         else if(g_enPartial && !g_enBe)  { g_enPartial = false; g_enBe = true;  }
         else if(!g_enPartial && g_enBe)  { g_enPartial = false; g_enBe = false; }
         else                             { g_enPartial = true;  g_enBe = true;  }
         g_tpTiers[0].enabled = g_enPartial;
      }
      else if(sparam == PREFIX + "Btn_GetRealEq")
      {
         double realEq = AccountInfoDouble(ACCOUNT_EQUITY);
         if(realEq > 0.0)
         {
            g_customEquity  = NormalizeDouble(realEq, 0);
            g_useLiveEquity = true;
            if(ObjectFind(0, PREFIX + "Ed_CustomEq") >= 0)
               ObjectSetString(0, PREFIX + "Ed_CustomEq", OBJPROP_TEXT, DoubleToString(g_customEquity, 0));
         }
      }
      else if(sparam == PREFIX + "Btn_News")    g_enNewsFilter = !g_enNewsFilter;
      else if(sparam == PREFIX + "Btn_EnSlot1") g_enSlot1      = !g_enSlot1;
      else if(sparam == PREFIX + "Btn_EnSlot2") g_enSlot2      = !g_enSlot2;
      else if(sparam == PREFIX + "Btn_EnSlot3") g_enSlot3      = !g_enSlot3;
      else if(sparam == PREFIX + "Btn_NewsTz")  g_newsTz       = (g_newsTz == TZ_LOCAL_PC) ? TZ_MT5_SERVER : TZ_LOCAL_PC;
      else if(sparam == PREFIX + "Btn_SyncSlTp")
      {
         string execSym = GetExecutionSymbol();
         int symPosCount = CountPositionsInScope(false);
         if(symPosCount == 0)
         {
            g_pinSizerEntry = false;
            g_atrCacheValid = false;
            ResetStandbySetupLock(_Period);
            ProcessCoreLogic();
            SetToastStatus(StringFormat("Đã tạo lại Setup & khóa khung %s", GetTfShortName(g_resolvedAtrTf)));
         }
         else
         {
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
               ulong t = PositionGetTicket(i);
               if(t > 0 && (PositionGetString(POSITION_SYMBOL) == _Symbol || PositionGetString(POSITION_SYMBOL) == execSym))
               {
                  long   posId   = PositionGetInteger(POSITION_IDENTIFIER);
                  double curVol  = PositionGetDouble(POSITION_VOLUME);
                  double actualE = PositionGetDouble(POSITION_PRICE_OPEN);
                  bool   isBuy   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
                  bool   partDone= (GlobalVariableCheck(AccountScopedGV("EAP82_PART_" + IntegerToString(posId))) ||
                                    GetPositionBitmask(PartialTpMaskKey(posId)) != 0);
                  bool   suppressHardTp = ShouldSuppressBrokerHardTpForPartial(curVol, partDone, actualE, g_sizerSlPrice, g_sizerTpPrice, isBuy);
                  double syncTP  = suppressHardTp ? 0.0 : NormalizeDouble(g_sizerTpPrice, _Digits);
                  ModifyPositionWithConfirmation(t, NormalizeDouble(g_sizerSlPrice, _Digits), syncTP);
               }
            }
            SetToastStatus("Đã đồng bộ SL/TP theo thước Sizer");
         }
      }
      else if(sparam == PREFIX + "Btn_NowBE")
      {
         string execSym = GetExecutionSymbol();
         double buyPV = 0.0, buyVol = 0.0, sellPV = 0.0, sellVol = 0.0;
         for(int k = PositionsTotal() - 1; k >= 0; k--)
         {
            ulong tk = PositionGetTicket(k);
            if(tk == 0) continue;
            string s = PositionGetString(POSITION_SYMBOL);
            if(s != _Symbol && s != execSym) continue;
            double vol   = PositionGetDouble(POSITION_VOLUME);
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            { buyVol += vol; buyPV += price * vol; }
            else
            { sellVol += vol; sellPV += price * vol; }
         }

         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong t = PositionGetTicket(i);
            if(t == 0) continue;
            string s = PositionGetString(POSITION_SYMBOL);
            if(s != _Symbol && s != execSym) continue;
            bool   isBuy    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
            double sideVol  = isBuy ? buyVol : sellVol;
            double sidePV   = isBuy ? buyPV  : sellPV;
            double sideVwap = (sideVol > 0.0) ? (sidePV / sideVol) : 0.0;
            double baseE    = (g_multiMode == MULTI_BASKET_VWAP && !g_mixedPositionFallback && sideVwap > 0.0)
                              ? sideVwap : PositionGetDouble(POSITION_PRICE_OPEN);
            double tp       = PositionGetDouble(POSITION_TP);
            double beSL     = (g_enCommonBe && g_multiMode == MULTI_BASKET_VWAP && !g_mixedPositionFallback && g_commonBePrice > 0.0)
                              ? g_commonBePrice
                              : (isBuy ? NormalizeDouble(baseE + g_bePoints * _Point, _Digits)
                                       : NormalizeDouble(baseE - g_bePoints * _Point, _Digits));
            ModifyPositionWithConfirmation(t, beSL, tp);
         }
         SetToastStatus("Đã dời SL về Hòa vốn (BE)");
      }
      else if(sparam == PREFIX + "Btn_Close50")
      {
         string execSym = GetExecutionSymbol();
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong t = PositionGetTicket(i);
            if(t > 0 && (PositionGetString(POSITION_SYMBOL) == _Symbol || PositionGetString(POSITION_SYMBOL) == execSym))
            {
               double vol  = PositionGetDouble(POSITION_VOLUME);
               double half = FloorLotStep(vol * 0.5);
               if(half >= SymbolInfoDouble(execSym, SYMBOL_VOLUME_MIN))
                  ClosePositionPartiallyByTicket(t, half);
            }
         }
         SetToastStatus("Đã gửi lệnh cắt 50% khối lượng");
      }
      else if(sparam == PREFIX + "Btn_CloseAll")
      {
         // Yêu cầu bấm xác nhận 2 lần trong vòng 3 giây để chống bấm nhầm nút ĐÓNG TẤT CẢ
         datetime nowClick = TimeLocal();
         if(g_lastCloseAllClickTime == 0 || (nowClick - g_lastCloseAllClickTime) > 3)
         {
            g_lastCloseAllClickTime = nowClick;
            SetToastStatus("Bấm [XÁC NHẬN?] thêm 1 lần nữa trong 3 giây để Đóng Tất Cả!");
            RebuildCleanPanel(false);
            return;
         }
         g_lastCloseAllClickTime = 0;
         CloseAllTradesAndOrders("Người dùng xác nhận ĐÓNG TẤT CẢ");
      }

      RebuildCleanPanel(false);
      ProcessCoreLogic();
   }
}

//+------------------------------------------------------------------+
//| Xử lý Giao dịch Thực tế: Đồng bộ Mobile, OCO, Virtual SL/TP & TG |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0 || !HistoryDealSelect(trans.deal))
      return;

   long   dealEntry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   long   dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   string dealSym   = HistoryDealGetString(trans.deal, DEAL_SYMBOL);

   // 1. Xử lý Lệnh Mở / Đóng từ bên ngoài (MT5 Mobile App / Web / EA khác)
   if((ulong)dealMagic != (ulong)InpTradeMagicNumber)
   {
      // Adopted OCO orders can originate from Mobile / third-party EAs.
      // Handle their fills BEFORE the external-magic early return.
      if(dealEntry == DEAL_ENTRY_IN)
      {
         ulong externalSourceOrder = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
         string externalOcoKey = AccountScopedGV("TD_OCOTK_" + IntegerToString((long)externalSourceOrder));
         if(externalSourceOrder > 0 && GlobalVariableCheck(externalOcoKey))
         {
            GlobalVariableDel(externalOcoKey);
            CancelOcoPending();
         }
      }
      if((dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY || dealEntry == DEAL_ENTRY_INOUT) && InpNotifyExternalTrades)
      {
         double closedVolume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
         double closedPnl    = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                             + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                             + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION)
                             + HistoryDealGetDouble(trans.deal, DEAL_FEE);
         string shot = (InpAutoScreenshotOnTrade && dealSym == _Symbol) ? CaptureChartScreenshot(true, "EXT_CLOSE") : "";
         QueueTradeDeskNotification(StringFormat("TradeDesk EXTERNAL CLOSE | %s | %.2f lot | P/L %.2f %s",
                                                 dealSym, closedVolume, closedPnl, AccountInfoString(ACCOUNT_CURRENCY)),
                                    InpTelegramOnClose, shot);
      }
      if(dealEntry == DEAL_ENTRY_IN)
      {
         if(InpNotifyExternalTrades)
         {
            string externalSide   = (HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? "BUY" : "SELL";
            double externalVolume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
            string shot = (InpAutoScreenshotOnTrade && dealSym == _Symbol) ? CaptureChartScreenshot(true, "EXT_OPEN") : "";
            QueueTradeDeskNotification(StringFormat("TradeDesk EXTERNAL OPEN | %s %s | %.2f lot | nguồn Mobile/Ngoài",
                                                    dealSym, externalSide, externalVolume),
                                       InpTelegramOnOpen, shot);
         }
         if(g_manageExternalOn)
            HandleExternalPositionEntry(trans.deal);
      }
      return;
   }

   // 2. Xử lý Lệnh của chính TradeDesk Pro v12
   long   positionId           = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   ulong  sourceOrder          = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
   string positionTpKey        = VirtualTPPositionKey(positionId);
   string positionSlKey        = VirtualSLPositionKey(positionId);
   string positionEmergencyKey = VirtualEmergencySLPositionKey(positionId);

   if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY)
   {
      double exitPrice  = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      double exitVolume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
      double exitPnl    = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                        + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                        + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION)
                        + HistoryDealGetDouble(trans.deal, DEAL_FEE);
      string shot = (InpAutoScreenshotOnTrade && dealSym == _Symbol) ? CaptureChartScreenshot(true, "CLOSE") : "";
      QueueTradeDeskNotification(StringFormat("TradeDesk CLOSED | %s | %.2f lot @ %s | P/L %.2f %s",
                                              dealSym, exitVolume,
                                              DoubleToString(exitPrice, (int)SymbolInfoInteger(dealSym, SYMBOL_DIGITS)),
                                              exitPnl, AccountInfoString(ACCOUNT_CURRENCY)),
                                 InpTelegramOnClose, shot);

      bool positionStillOpen = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong liveTicket = PositionGetTicket(i);
         if(liveTicket > 0 && PositionGetInteger(POSITION_IDENTIFIER) == positionId)
         {
            positionStillOpen = true;
            break;
         }
      }
      if(!positionStillOpen)
      {
         GlobalVariableDel(positionTpKey);
         GlobalVariableDel(positionSlKey);
         GlobalVariableDel(positionEmergencyKey);
         ClearPositionMasks(positionId);
         ObjectDelete(0, VIS_PREFIX + "VTP_" + IntegerToString(positionId));
         ObjectDelete(0, VIS_PREFIX + "VSL_" + IntegerToString(positionId));
      }
      return;
   }

   if(dealEntry != DEAL_ENTRY_IN)
      return;

   long   entryType   = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   bool   entryIsBuy  = (entryType == DEAL_TYPE_BUY);
   double entryPrice  = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double entryVolume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);

   // Ghi nhận khối lượng gốc ban đầu cho Ma trận 10 tầng Partial TP / SL
   if(positionId > 0 && entryVolume > 0.0 && !GlobalVariableCheck(InitialVolKey(positionId)))
      GlobalVariableSet(InitialVolKey(positionId), entryVolume);

   string shot = (InpAutoScreenshotOnTrade && dealSym == _Symbol) ? CaptureChartScreenshot(true, "OPEN") : "";
   QueueTradeDeskNotification(StringFormat("TradeDesk OPENED | %s %s | %.2f lot @ %s | Deal #%I64u",
                                           dealSym, entryIsBuy ? "BUY" : "SELL", entryVolume,
                                           DoubleToString(entryPrice, (int)SymbolInfoInteger(dealSym, SYMBOL_DIGITS)),
                                           trans.deal),
                              InpTelegramOnOpen, shot);

   // Chuyển giao Virtual TP / Virtual SL từ Lệnh chờ sang Vị thế khi lệnh chờ vừa khớp
   string orderTpKey = VirtualTPOrderKey(sourceOrder);
   if(GlobalVariableCheck(orderTpKey))
   {
      GlobalVariableSet(positionTpKey, GlobalVariableGet(orderTpKey));
      GlobalVariableDel(orderTpKey);
      GlobalVariableSet(AccountScopedGV("EAP82_INITDONE_" + IntegerToString(positionId)), 1.0);
   }
   string orderSlKey        = VirtualSLOrderKey(sourceOrder);
   string orderEmergencyKey = VirtualEmergencySLOrderKey(sourceOrder);
   if(GlobalVariableCheck(orderSlKey))
   {
      GlobalVariableSet(positionSlKey, GlobalVariableGet(orderSlKey));
      if(GlobalVariableCheck(orderEmergencyKey))
         GlobalVariableSet(positionEmergencyKey, GlobalVariableGet(orderEmergencyKey));
      GlobalVariableSet(AccountScopedGV("EAP82_INITDONE_" + IntegerToString(positionId)), 1.0);
      GlobalVariableDel(orderSlKey);
      GlobalVariableDel(orderEmergencyKey);
   }

   // Kiểm tra nếu lệnh vừa khớp thuộc nhóm OCO -> lập tức hủy các lệnh chờ OCO còn lại
   string dealComment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   if(StringFind(dealComment, "TDOCO_") != 0 && sourceOrder > 0 && HistoryOrderSelect(sourceOrder))
      dealComment = HistoryOrderGetString(sourceOrder, ORDER_COMMENT);

   string adoptedOcoKey = AccountScopedGV("TD_OCOTK_" + IntegerToString((long)sourceOrder));
   if(StringFind(dealComment, "TDOCO_") == 0 || GlobalVariableCheck(adoptedOcoKey))
   {
      GlobalVariableDel(adoptedOcoKey);
      CancelOcoPending();
   }
}
//+------------------------------------------------------------------+
