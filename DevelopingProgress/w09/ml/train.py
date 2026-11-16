"""Train two real, compact MLPs. Only NumPy is required; no remote service.

Original synthetic notices; holdout changes date/time/place phrasing and subject vocabulary.
Reported scores describe this synthetic holdout, not real campus accuracy.
"""
from pathlib import Path
import argparse, hashlib, json, random, time, struct
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
CLASSES = ['作业', '出行', '会议', '活动', '考试', '其他']
ROLES = ['标题', '日期', '时间', '截止', '地点', '其他']
DIM = 512

def features(s):
    # Identical unsigned FNV-1a over UTF-16 code units in ArkTS.
    s = ''.join(s.lower().split())
    encoded=s.encode('utf-16-le');s=struct.unpack('<'+'H'*(len(encoded)//2),encoded)[:1000]
    out = np.zeros(DIM, np.float32)
    for n in (1, 2):
        for i in range(len(s)-n+1):
            h = 2166136261
            for c in s[i:i+n]: h = ((h ^ c)*16777619) & 0xffffffff
            out[h % DIM] += 1
    return out / max(float(np.linalg.norm(out)), 1.)

def corpus(seed, count, holdout=False):
    rng = random.Random(seed)
    subjects=(['数据结构','艺术欣赏','机械设计','数值分析','逻辑基础','数字电路'] if not holdout else ['环境科学','移动应用','统计学','文学导论'])
    subjects2=(['小组','项目','班委','研究','年级','学术'] if not holdout else ['科研','学生组织','评奖','课程设计'])
    places = ['教学楼A102','创新楼301','综合楼B205'] if not holdout else ['逸夫楼C406','兴庆校区东门','主楼D208']
    docs, lines = [], []
    for i in range(count):
        k=i%6; subject=rng.choice(subjects); group=rng.choice(subjects2)
        verbs=['参加','完成','提交','办理','准备','进行']
        if k==0: title=rng.choice(['提交{}作业','完成{}实验报告','递交{}作业材料','{}作业提交']).format(subject)
        elif k==1: title=rng.choice(['乘坐{}次列车出行','乘{}航班前往上海','{}列车前往西安','{}车次出发']).format(rng.choice(['G970','D123','G456','MU216']))
        elif k==2: title=rng.choice(['参加{}会议','{}讨论会议','召开{}会议','{}会议安排']).format(group)
        elif k==3: title=rng.choice(['参加{}社团活动','{}志愿活动','报名{}活动','{}校园活动']).format(group)
        elif k==4: title=rng.choice(['参加{}考试','{}期末考试','准备{}考试','{}考试安排']).format(subject)
        else: title=rng.choice(['办理校园卡补办','领取快递包裹','到校医院复查','去图书馆还书','购买生活用品','清理宿舍书架'])
        date=f'2027-{rng.randint(1,12):02d}-{rng.randint(1,28):02d}'
        hour=rng.randint(8,18); end=hour+rng.randint(1,3)
        loc=rng.choice(places)
        prefix = rng.choice(['通知：','安排：','提醒：']) if not holdout else rng.choice(['请留意：','新消息：'])
        d=(f'日期：{date}' if not holdout else f'安排在 {date}')
        t=(f'时间：{hour:02d}:00-{end:02d}:00' if not holdout else f'从 {hour:02d}:00 到 {end:02d}:00')
        p=(f'地点：{loc}' if not holdout else f'请到 {loc}')
        rows=[(prefix+title,0),(d,1),(t,2),(p,4)]
        if k==0:
            rows.append((f'提交截止：{date} 23:59' if not holdout else f'务必于 {date} 22:00 前提交',3))
        rows.append((rng.choice(['请相互转告','请准时参加','如有问题请联系负责人']) if not holdout else rng.choice(['如有疑问请联系老师','请提前做好准备']),5))
        if i%3==0: rng.shuffle(rows)
        docs.append(('\n'.join(r[0] for r in rows),k))
        lines.extend(rows)
    return docs, lines

def train(name, rows, testrows, labels, epochs, rng):
    x=np.stack([features(t) for t,y in rows]); y=np.array([y for t,y in rows])
    tx=np.stack([features(t) for t,y in testrows]); ty=np.array([y for t,y in testrows])
    dims=[DIM,64,32,len(labels)]
    w=[(rng.normal(size=(a,b))*np.sqrt(2/a)).astype('float32') for a,b in zip(dims,dims[1:])]
    b=[np.zeros(d,np.float32) for d in dims[1:]]
    params=w+b; moments=[np.zeros_like(p) for p in params]; squares=[np.zeros_like(p) for p in params]
    step=0
    def forward(a):
        h1=np.maximum(a@w[0]+b[0],0); h2=np.maximum(h1@w[1]+b[1],0)
        z=h2@w[2]+b[2]; z-=z.max(axis=1,keepdims=True); p=np.exp(z); p/=p.sum(axis=1,keepdims=True)
        return h1,h2,p
    for epoch in range(epochs):
        order=rng.permutation(len(y)); loss=0.
        for off in range(0,len(y),128):
            ix=order[off:off+128]; a=x[ix]; target=y[ix]; h1,h2,p=forward(a)
            loss-=float(np.log(p[np.arange(len(ix)),target]+1e-9).sum())
            dz=p.copy(); dz[np.arange(len(ix)),target]-=1; dz/=len(ix)
            dw2=h2.T@dz; db2=dz.sum(0); dh2=(dz@w[2].T)*(h2>0)
            dw1=h1.T@dh2; db1=dh2.sum(0); dh1=(dh2@w[1].T)*(h1>0)
            dw0=a.T@dh1; db0=dh1.sum(0)
            step+=1
            for j,g in enumerate([dw0,dw1,dw2,db0,db1,db2]):
                moments[j]=.9*moments[j]+.1*g; squares[j]=.999*squares[j]+.001*g*g
                params[j]-=.002*(moments[j]/(1-.9**step))/(np.sqrt(squares[j]/(1-.999**step))+1e-8)
        if epoch%5==0 or epoch==epochs-1: print(name,epoch+1,'loss',round(loss/len(y),5),flush=True)
    _,_,p=forward(tx); pred=p.argmax(1); cm=np.zeros((len(labels),len(labels)),int)
    for a,c in zip(ty,pred): cm[a,c]+=1
    f1=[]
    for j in range(len(labels)):
        tp=int(cm[j,j]); f1.append(2*tp/max(int(cm[j,:].sum()+cm[:,j].sum()),1))
    model={'format':'jt-mlp-1','inputDim':DIM,'labels':labels,'sizes':dims,
           'weights':[a.round(7).flatten().tolist() for a in w], 'biases':[a.round(7).tolist() for a in b]}
    report={'trainExamples':len(rows),'testExamples':len(testrows),'accuracy':float((pred==ty).mean()),
            'macroF1':float(np.mean(f1)),'perClassF1':dict(zip(labels,f1)),'confusionMatrix':cm.tolist()}
    vectors=[]
    for text,_ in testrows[:12]:
        _,_,prob=forward(features(text)[None,:]); vectors.append({'text':text,'probabilities':prob[0].tolist()})
    return model,report,vectors

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--epochs',type=int,default=25); a=ap.parse_args()
    train_docs,train_lines=corpus(731,3600); test_docs,test_lines=corpus(923,600,True)
    rng=np.random.default_rng(7127); models={}; reports={}; parity={}; started=time.time()
    for name,tr,te,labels in [('classifier',train_docs,test_docs,CLASSES),('roles',train_lines,test_lines,ROLES)]:
        models[name],reports[name],parity[name]=train(name,tr,te,labels,a.epochs,rng)
    raw=ROOT/'entry/src/main/resources/rawfile/ml'; raw.mkdir(parents=True,exist_ok=True)
    for name,model in models.items(): (raw/f'{name}.json').write_text(json.dumps(model,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    report={'seed':7127,'epochs':a.epochs,'seconds':round(time.time()-started,2),'engine':'NumPy forward/backprop + Adam, 512→64→32→6, ReLU/ReLU/softmax',
      'data':'Original synthetic Chinese campus notices. Heldout subjects, organizers, places, date/time phrasing and notice prefixes; task-title patterns are shared. No personal data.',
      'limitation':'Synthetic holdout is NOT real campus accuracy. OCR uses separately licensed pretrained Tesseract LSTM; not trained here.',
      'models':reports,'sha256':{n:hashlib.sha256((raw/f'{n}.json').read_bytes()).hexdigest() for n in models}}
    (ROOT/'ml/evaluation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    (ROOT/'ml/parity.json').write_text(json.dumps(parity,ensure_ascii=False),encoding='utf8')
    print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)

if __name__=='__main__': main()
