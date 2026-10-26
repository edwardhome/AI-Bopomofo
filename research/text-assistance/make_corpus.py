"""Individually authored synthetic examples; no private input or template multiplication."""
import json
from pathlib import Path
CHINESE = '''今天的天汽很好。|今天的天氣很好。
請把會議記祿寄給我。|請把會議紀錄寄給我。
這份報告需要重新編輯與校隊。|這份報告需要重新編輯與校對。
我們明天再討倫這件事。|我們明天再討論這件事。
請確認收件人的地止。|請確認收件人的地址。
這台電腦的記憶提不足。|這台電腦的記憶體不足。
檔案已經順利儲純。|檔案已經順利儲存。
請先備份重要資聊。|請先備份重要資料。
這個問題已經解絕了。|這個問題已經解決了。
我需要申請一張發漂。|我需要申請一張發票。
今天下午有一場演獎。|今天下午有一場演講。
請在期限內繳交申請標。|請在期限內繳交申請表。
捷運站的出口正在維羞。|捷運站的出口正在維修。
他對這項工作很負則。|他對這項工作很負責。
請耐心等後通知。|請耐心等候通知。
這個產品的品直很好。|這個產品的品質很好。
我們需要更多實驗正據。|我們需要更多實驗證據。
早餐店今天提早打洋。|早餐店今天提早打烊。
這條路正在進行施公。|這條路正在進行施工。
明天的會議延後半小實。|明天的會議延後半小時。
請把窗戶關緊以免下雨滲誰。|請把窗戶關緊以免下雨滲水。
這是一個值得參考的建義。|這是一個值得參考的建議。
我已經收到您的回復信鍵。|我已經收到您的回復信件。
這家餐廳的服務很周稻。|這家餐廳的服務很周到。
請遵守公共場所的歸定。|請遵守公共場所的規定。
新的軟體版本修正了許多錯誤與缺現。|新的軟體版本修正了許多錯誤與缺陷。
這筆交易需要再次確任。|這筆交易需要再次確認。
我們應該尊重不同的觀典。|我們應該尊重不同的觀點。
這項研究的結果相當有趣且直得注意。|這項研究的結果相當有趣且值得注意。
請將垃圾做好分淚。|請將垃圾做好分類。
這場比賽的競爭非常激列。|這場比賽的競爭非常激烈。
運動之後記得補充水份與電解直。|運動之後記得補充水份與電解質。
電池的電量已經耗徑。|電池的電量已經耗盡。
這個帳號尚未完成驗正。|這個帳號尚未完成驗證。
密碼請妥善保管不要外洩給陌生仁。|密碼請妥善保管不要外洩給陌生人。
我的行事曆新增了一個提刑。|我的行事曆新增了一個提醒。
請問最近的郵局在哪裡可以寄性？|請問最近的郵局在哪裡可以寄信？
大家一起整理辦公室的環竟。|大家一起整理辦公室的環境。
這本書的內容相當豐付。|這本書的內容相當豐富。
請勿在圖書館內大聲喧華。|請勿在圖書館內大聲喧嘩。
新的政策將於下個月實十。|新的政策將於下個月實施。
他正在準備研究所的口是。|他正在準備研究所的口試。
這套系統可以自動產生圖標與報告。|這套系統可以自動產生圖表與報告。
訊號受到附近設備的干饒。|訊號受到附近設備的干擾。
工程師正在檢查網路連現。|工程師正在檢查網路連線。
請依照步驟完成安裝程續。|請依照步驟完成安裝程序。
這個功能可以提高工作效綠。|這個功能可以提高工作效率。
開會之前請先閱讀附鍵。|開會之前請先閱讀附件。
所有測試案例都已經通果。|所有測試案例都已經通過。
請保留原始檔案方便日後追縱。|請保留原始檔案方便日後追蹤。'''
ENGLISH = '''Please send teh report.|Please send the report.
I will recieve the package tomorrow.|I will receive the package tomorrow.
This is a seperate document.|This is a separate document.
The meeting is definately confirmed.|The meeting is definitely confirmed.
We need to accomodate more guests.|We need to accommodate more guests.
The address is not availble yet.|The address is not available yet.
Please check the enviroment settings.|Please check the environment settings.
Your subscription was succesful.|Your subscription was successful.
I forgot my passwrod again.|I forgot my password again.
This change is neccessary for safety.|This change is necessary for safety.
The library contains useful informtion.|The library contains useful information.
Please update the documantation.|Please update the documentation.
I appreciate your patiance.|I appreciate your patience.
The server is currenly offline.|The server is currently offline.
We should discuss this tommorow.|We should discuss this tomorrow.
This is an excelent idea.|This is an excellent idea.
Please confirm your attendence.|Please confirm your attendance.
The project has a strict deadlien.|The project has a strict deadline.
I am writting a short note.|I am writing a short note.
They recieved our invitation.|They received our invitation.
We need a reliable soluton.|We need a reliable solution.
Please use the correct formatt.|Please use the correct format.
The application needs permision.|The application needs permission.
This feature improves accesibility.|This feature improves accessibility.
We found an unexpected excepetion.|We found an unexpected exception.
The connection was interupted.|The connection was interrupted.
Please restart the computre.|Please restart the computer.
I have a simple questoin.|I have a simple question.
This sample demonstrates the diffrence.|This sample demonstrates the difference.
The new design is more flexble.|The new design is more flexible.
Please verify the mesage before sending.|Please verify the message before sending.
This behavior is inconsistant.|This behavior is inconsistent.
The file contains a duplciate entry.|The file contains a duplicate entry.
We should preserve compatiblity.|We should preserve compatibility.
The document includes an introducton.|The document includes an introduction.
Please provide a clear explanaton.|Please provide a clear explanation.
This is a temporary workarond.|This is a temporary workaround.
The process completed automaticly.|The process completed automatically.
We need to measure the latancy.|We need to measure the latency.
The results are reproducable.|The results are reproducible.
Please record the temperatue.|Please record the temperature.
This experiment requires precison.|This experiment requires precision.
The response arrived immediatly.|The response arrived immediately.
I prefer a concise sumary.|I prefer a concise summary.
The team reached an agrement.|The team reached an agreement.
This version includes several improvments.|This version includes several improvements.
Please review the requirments.|Please review the requirements.
The resource is temporarily unavailble.|The resource is temporarily unavailable.
The operation was cancelled intentionaly.|The operation was cancelled intentionally.
We should investigate the root cuase.|We should investigate the root cause.'''
PROTECTED = '''Use `teh_value` exactly.
Keep `recieve()` in the example.
Open src/config.json before editing.
Visit https://example.com/teh for details.
The variable is qz_module7.
Install PySide6 for this project.
Our project uses SystemVerilog.
Use HTTP for this example.
Do not change RTX4090.
Run `git checkout feature/teh` now.
# Project status
## Installation steps
**Keep this emphasis**
*Keep this italic text*
[Read the guide](https://example.org/guide)
![Diagram](images/diagram.png)
> Keep this quoted sentence.
- Keep this list item.
1. Keep this numbered item.
The version is 0.4.0.
The amount is 12.50 dollars.
Store it in /usr/local/bin/tool.
Use foo.bar as the file name.
The address is team@example.com.
Keep the literal `print("helllo")`.
Use the flag `--no-verify`.
Set `MAX_RETRY` to 3.
Keep `user_name` unchanged.
The type is MyWidgetFactory.
The command is `npm run build`.
Save the table as report_2026.csv.
Use `a != b` for comparison.
Keep the expression `x += 1`.
The branch is fix/typo_handler.
The path is C:\\work\\teh.txt.
Open README.md in the editor.
The package is tensorflow2.
Run `python -m pytest`.
Use the key `Ctrl+Shift+P`.
Keep the unclosed code `recieve
Use the placeholder ${HOME}.
Set `timeout_ms=5000`.
The release tag is v0.5.0.
Keep the acronym FPGA.
Use the custom term mybrand.
The custom word is qzword.
請保留變數 qz_module7。
請安裝 PySide6 套件。
路徑是 src/main.swift。
標題是 **測試結果**。'''
CORRECT = '''今天下午我們會一起討論專案進度。
請先備份資料再更新系統。
這個功能目前仍在測試中。
我想在週末去圖書館看書。
請將會議紀錄寄給所有同事。
明天早上九點開始上課。
這份報告需要清楚的數據支持。
運動之後要記得補充水分。
請尊重每個人的不同意見。
我們已經完成第一階段的工作。
這家咖啡店的環境很安靜。
請在離開之前確認門窗關好。
新的方法可以節省不少時間。
這個例子有助於理解問題。
我正在學習如何使用這套工具。
如果遇到問題可以查看說明文件。
謝謝您提供詳細的回覆。
這項決定需要更多討論。
請保留原始文字以便比較。
我們希望輸入時能保持流暢。
修改完成後請重新執行測試。
這些資料只會保存在本機。
他對新技術充滿好奇。
這個句子沒有需要修正的錯字。
我們下次會議再確認結果。
Please keep the original text.
The meeting starts at noon.
I would like to learn more about this topic.
This feature is still being tested.
We need more evidence before deciding.
Thank you for your careful review.
Please back up your files first.
The application works without a network connection.
I prefer short and clear explanations.
We can discuss the details tomorrow.
The results look consistent so far.
Please do not change the variable names.
This example explains the basic idea.
We should test the failure cases as well.
The document is ready for review.
I am looking forward to your reply.
Please select a suggestion before accepting it.
The original order should remain unchanged.
This approach protects user privacy.
We will measure performance separately.
The current version supports both languages.
Please use the existing configuration.
This sentence does not contain a spelling error.
The task can continue in the background.
We should verify the result before publishing.'''
def build():
    rows=[]
    for category, block in [('chinese',CHINESE),('english',ENGLISH),('protected',PROTECTED),('correct',CORRECT)]:
        lines=block.splitlines()
        assert len(lines)==50, (category,len(lines))
        for i,line in enumerate(lines):
            parts=line.split('|') if category in ('chinese','english') else [line,line]
            assert len(parts)==2
            rows.append(dict(id=f'{category}-{i+1:02}', category=category, text=parts[0], expected=[parts[1]],
                             isEnglish=parts[0].isascii(), protectedWords=['mybrand','qzword']))
    return rows

if __name__ == "__main__":
    rows = build()
    Path(__file__).with_name("corpus-200.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2)+"\n")
    print(f"Wrote {len(rows)} independently authored synthetic cases")
