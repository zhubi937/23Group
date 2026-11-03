from PIL import Image,ImageDraw,ImageFont
from pathlib import Path
base=Path('entry/src/main/resources/rawfile/samples')
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',30)
small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',22)
sets={'train':['G970','9月10日（周四）','10:56','14:46','成都东','西安北','历时3小时50分','检票口：A16 / A17 / B16 / B17'], 'notice':['移动应用设计作业通知','课程：移动应用开发','提交截止：2026年12月18日 23:59','地点：在线提交','完成应用原型与工程说明'], 'update':['移动应用设计作业延期通知','课程：移动应用开发','提交截止：2026年12月20日 23:59','地点：在线提交','请以本次延期通知为准']}
for k,lines in sets.items():
 im=Image.new('RGB',(800,820),(255,255,255));d=ImageDraw.Draw(im)
 d.rectangle((0,0,800,7),fill='#C72C33');d.text((60,60),'截图成事 / 自制演示样例',font=small,fill='#C72C33')
 for i,t in enumerate(lines):d.text((60,140+i*72+6),t,font=font,fill='#292D30')
 d.text((60,758),'测试内容，无真实乘车人、账号或二维码',font=small,fill='#78746C')
 im.save(base/(k+'.png'))
