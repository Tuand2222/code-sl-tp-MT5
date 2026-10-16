# Professional Multi-Asset Risk Manager — Hướng dẫn sử dụng

## Mục đích

Chỉ báo tính **quy mô vị thế theo rủi ro** cho cổ phiếu, forex, hàng hóa/futures và crypto. Nó không tạo tín hiệu mua/bán và không tự đặt lệnh.

Kết quả chính:

- Khối lượng vào lệnh đã làm tròn xuống theo bước broker.
- Rủi ro tiền mặt và phần trăm vốn sau phí/buffer.
- Notional và margin ước tính.
- Entry, Stop, TP1–TP3; khối lượng thoát từng phần.
- R:R ròng ước tính cho sản phẩm P&L tuyến tính.
- Cảnh báo cấu hình và alert khi giá chạm mức.

## Cài đặt

1. Mở TradingView → **Pine Editor**.
2. Mở file `Professional_Multi_Asset_Risk_Manager.pine`, sao chép toàn bộ mã và dán vào Pine Editor.
3. Chọn **Save** → **Add to chart**.
4. Mở Settings của chỉ báo và nhập vốn, rủi ro, Entry/Stop, thông số sản phẩm và phí.
5. Đối chiếu hàng **Mô hình P&L**, **Loss / qty**, **FX**, **bước khối lượng** và **Notional** với hợp đồng thực tế của broker trước khi dùng kết quả.

Bảng có ba trạng thái: **KHÔNG HỢP LỆ** (không được dùng qty), **CẦN XÁC NHẬN** (phép tính chạy nhưng còn giả định cần kiểm tra) và **SẴN SÀNG** (các kiểm tra cấu hình chính đã qua). “Sẵn sàng” vẫn không phải khuyến nghị giao dịch.

## Chọn mô hình P&L

| Mô hình | Khi nên dùng | Dữ liệu cần kiểm tra |
|---|---|---|
| `Auto Linear` | Cổ phiếu, crypto spot/linear perpetual, futures niêm yết khi metadata đúng | `syminfo.pointvalue`, `syminfo.mincontract` |
| `Manual Value/Point` | Forex theo lot, vàng/dầu CFD, hợp đồng có contract multiplier riêng | Giá trị bằng tiền quote khi giá chạy 1.0 cho 1 qty |
| `Manual Tick Value` | Futures/CFD có tick value do sàn/broker công bố | Tick value, tiền tệ của tick value |
| `Direct Loss/Qty` | Inverse/quanto crypto hoặc sản phẩm phi tuyến | Lỗ tại Stop của 1 qty, lấy từ contract calculator/broker |

Không chọn mô hình chỉ dựa vào nhãn “forex”, “crypto” hay “hàng hóa”. Ví dụ BTC spot, linear perpetual và inverse perpetual có công thức P&L khác nhau.

## Cấu hình mẫu

### Cổ phiếu

- Mô hình: `Auto Linear`.
- Bước/min qty: nhập thủ công `1` share; chỉ dùng Auto sau khi đối chiếu feed với broker.
- Đơn vị qty: `Shares`.
- Margin: leverage `1x` cho tài khoản cash.
- Phí: nhập phí/share hoặc % notional theo broker.

### Futures hàng hóa/chỉ số

- Thử `Auto Linear`; kiểm tra point value trên bảng với đặc tả hợp đồng.
- Bước qty thường là `1 contract`.
- Đơn vị qty: `Contracts`.
- Nên chọn `Margin / qty thủ công` và nhập initial margin của broker/sàn thay vì suy từ leverage.

### Forex

Có hai cách phổ biến:

1. **Qty là base units:** dùng `Auto Linear` nếu feed cho point value = 1; chọn đơn vị `Units`; nhập bước qty theo broker và `Native qty trong 1 lot = 100000` để xem lot quy đổi.
2. **Qty là lots:** dùng `Manual Value/Point`; với lot chuẩn thường nhập `100000` quote units cho biến động giá 1.0; bước `0.01`, min `0.01`, `Native qty trong 1 lot = 1`, đơn vị `Lots`.

Ví dụ EURUSD lot chuẩn, Entry 1.1000 và Stop 1.0950: khoảng giá 0.0050 × 100,000 = 500 USD rủi ro/lot trước phí và slippage.

### Vàng XAUUSD CFD

Thông số tùy broker. Nếu 1 lot = 100 oz, có thể bắt đầu với:

- `Manual Value/Point = 100`.
- Bước qty `0.01`, min `0.01`.
- Đơn vị qty `Lots`; `Native qty trong 1 lot = 1`.
- Nhập spread/slippage và commission đúng tài khoản.

Không dùng cấu hình này nếu broker quy định contract size khác.

### Crypto spot hoặc linear perpetual

- Mô hình thường là `Auto Linear` với multiplier 1 coin, nhưng phải kiểm tra đặc tả sàn.
- Override bước/min qty theo symbol tại sàn.
- Chọn rõ đơn vị `Coins` hoặc `Contracts` theo sản phẩm; không để `Native qty` sau khi đã xác nhận.
- Nhập taker fee vào **Phí % notional / mỗi chiều**.
- Với perpetual, nhập leverage và bật margin cap nếu muốn giới hạn sức mua.

### Crypto inverse/quanto

- Chọn `Direct Loss/Qty`.
- Bắt buộc dùng Entry và Stop thủ công cố định; cập nhật `Direct Loss/Qty` mỗi khi thay đổi hai mức này.
- Bắt buộc đặt TP bằng **Giá thủ công**; không dùng TP theo R vì P&L inverse/quanto không tuyến tính theo khoảng giá.
- Dùng calculator của sàn để lấy lỗ của 1 contract tại Stop, đã gồm execution buffer mong muốn.
- Đặt **Tổng tick bất lợi** bằng `0`; buffer spread/slippage/gap nhỏ phải được gộp trực tiếp vào số `Direct Loss/Qty`.
- Không dùng trường phí `% notional` trong Direct mode. Quy đổi toàn bộ phí thành **phí tiền mặt / qty / round-trip**.
- Nếu bật margin cap, chọn **Margin / qty thủ công**. `Notional / qty` trong Direct mode chỉ để tham khảo hiển thị.
- R:R ròng hiển thị `N/A`, vì không thể suy P&L mục tiêu phi tuyến một cách an toàn chỉ từ mức giá.

## Công thức cốt lõi

```text
Ngân sách risk = vốn × risk %

Loss/qty = lỗ do Entry→Stop
         + spread/slippage/gap buffer
         + phí biến đổi round-trip

Raw qty = (ngân sách risk − phí cố định) / Loss/qty

Qty cuối = floor(Raw qty / bước broker) × bước broker
```

Nếu bật giới hạn margin hoặc max qty, chỉ báo lấy giá trị nhỏ nhất giữa khối lượng theo risk và các giới hạn đó. Margin cap dự phòng cả phí cố định và phí biến đổi đã nhập. Chỉ báo **không bao giờ nâng qty lên mức tối thiểu hoặc min notional** nếu việc đó làm vượt ngân sách rủi ro; nó trả `NO TRADE`.

Khối lượng TP được phân theo phương pháp phần dư lớn nhất trên số bước broker. Mặc định chỉ dùng TP1 với 100% khối lượng để cả kế hoạch 1 contract vẫn thực thi được; giảm TP1 và tăng TP2 nếu muốn chia thêm tranche, phần còn lại tự vào TP3. Cột TP hiển thị `tỷ lệ đặt → tỷ lệ thực` sau làm tròn. Nếu một tranche đang bật nhưng nhỏ hơn min qty, kế hoạch bị đánh dấu không hợp lệ; hãy giảm số tranche thay vì ép khối lượng lên.

## Ý nghĩa chi phí

- **Tổng tick bất lợi:** buffer round-trip cho spread, slippage và một phần gap nhỏ. Nó được cộng vào khoảng lỗ và trừ khỏi khoảng lời ở ba mô hình tuyến tính. Với `Direct Loss/Qty`, trường này phải bằng `0` và buffer phải được gộp vào Direct Loss.
- **Phí / qty / round-trip:** commission bằng tiền tài khoản cho 1 qty qua cả entry và exit.
- **Phí % notional / mỗi chiều:** ví dụ 0.05% thì nhập `0.05`.
- **Phí cố định toàn lệnh:** chi phí cố định dự kiến cho toàn bộ entry và các lệnh thoát.

Gap lớn, thanh khoản kém và market impact vẫn có thể làm lỗ thực tế vượt con số dự kiến.

## Quy đổi tiền tệ

Chế độ tự động dùng tỷ giá tham chiếu theo ngày của TradingView từ `syminfo.currency` sang tiền tài khoản. Nếu tỷ giá trả về `N/A`, chuyển sang **Thủ công** và nhập số đơn vị tiền tài khoản tương ứng với 1 đơn vị tiền quote. Chỉ báo không âm thầm giả định tỷ giá bằng 1.

## Alert

Chỉ báo cung cấp các điều kiện chạm/vượt mức độc lập; điều kiện theo hướng cũng bắt trường hợp giá gap qua mức:

- Giá chạm Entry.
- Giá chạm Stop.
- Giá chạm TP1, TP2 hoặc TP3 có khối lượng thoát lớn hơn 0.

Alert chỉ hoạt động với kế hoạch **STATIC**: Entry là giá thủ công và Stop là giá thủ công, `% từ Entry` hoặc `Số tick`; Stop theo ATR và Entry theo giá hiện tại là **DYNAMIC**. TP có thể là giá thủ công hoặc được suy cố định theo R (riêng Direct mode bắt buộc TP thủ công). Trước khi tạo alert Stop/TP, bật **Arm alert Stop/TP (đã vào lệnh)**. Khi tạo alert, chọn tần suất **Once Per Bar** để nhận ngay trong nến sống và tránh lặp thông báo. Đây chỉ là sự kiện giá chạm/vượt mức, không phải trạng thái vị thế từ broker và không xác định thứ tự intrabar nếu một nến đi qua nhiều mức. Sau khi đổi symbol, timeframe, mức giá hoặc input, hãy xóa và tạo lại alert vì TradingView lưu snapshot của script và cấu hình tại thời điểm tạo.

## Giới hạn quan trọng

- Pine indicator không đọc trực tiếp equity, free margin, vị thế mở hoặc quy tắc lot của tài khoản broker; các số này phải nhập thủ công.
- `syminfo.mincontract` là thông tin từ symbol/exchange, không bảo đảm trùng bước khối lượng tại broker.
- Margin cộng dự phòng phí vẫn là ước tính; futures, option, short stock và margin theo tier cần dữ liệu broker riêng.
- Chỉ báo chưa tính funding, borrow fee, thuế, liquidation, tiered margin hoặc market impact.
- Stop-loss là mức rủi ro lập kế hoạch, không phải cam kết mức lỗ tối đa.
- Nên dùng chart nến chuẩn; chart phi tiêu chuẩn có thể dùng giá tổng hợp.

## Checklist trước khi đặt lệnh

- Vốn và tiền tệ tài khoản đúng.
- Entry/Stop đúng phía Long hoặc Short.
- Point value/tick value/Direct Loss đúng hợp đồng.
- Bước khối lượng và min qty đúng broker.
- Đơn vị qty đã chọn đúng: units, lots, contracts, shares hoặc coins.
- Min notional của sàn/broker đã được nhập nếu có.
- FX không phải `N/A`.
- Phí và execution buffer không bị bỏ quên.
- Margin khả dụng đủ.
- Tổng khối lượng TP1 + TP2 + TP3 bằng khối lượng entry; không tranche nào nhỏ hơn min qty.
- Risk thực tính không vượt ngân sách đã đặt.
