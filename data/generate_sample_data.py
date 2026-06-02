#!/usr/bin/env python3
"""Generate the synthetic, labeled sample dataset for the Fraud SQL Detection Pack.

Seeded (random.seed(42)) so output is fully reproducible. Writes four CSVs
into this directory: sample_accounts, sample_transactions, sample_login_events,
sample_labels. All data is synthetic — no real PII. Run: python generate_sample_data.py
"""
import csv, random, datetime, hashlib, os
random.seed(42)
import os
OUT=os.path.dirname(os.path.abspath(__file__))
os.makedirs(OUT, exist_ok=True)
base=datetime.datetime(2026,5,1,8,0,0)
def ts(mins): return (base+datetime.timedelta(minutes=mins)).strftime("%Y-%m-%d %H:%M:%S")
countries=["US","GB","CA","DE","FR","BR","NG","IN"]
mccs=["GROCERY","DIGITAL_GOODS","TRAVEL","GAMING","ELECTRONICS","CHARITY"]

accounts=[]
for i in range(1,41):
    aid=f"ACC{i:04d}"
    accounts.append({"account_id":aid,"email":f"user{i}@example.com",
        "country":random.choice(countries),
        "account_created_at":(base-datetime.timedelta(days=random.randint(5,800))).strftime("%Y-%m-%d %H:%M:%S"),
        "kyc_status":random.choices(["VERIFIED","PENDING","FAILED"],[0.8,0.15,0.05])[0],
        "is_high_risk_segment": random.random()<0.15})

txns=[]; labels=[]; logins=[]
tid=0; lid=0
def card(s): return "card_"+hashlib.md5(s.encode()).hexdigest()[:12]
def newtxn(acc,minute,amount,res,reason,ip,dev,merch,mcc,cardfp,bincc,cp=False):
    global tid; tid+=1
    t=f"TX{tid:05d}"
    txns.append({"transaction_id":t,"account_id":acc,"card_fingerprint":cardfp,
        "merchant_id":merch,"merchant_category":mcc,"transaction_amount":f"{amount:.2f}",
        "currency":"USD","auth_result":res,"decline_reason":reason,"ip_address":ip,
        "device_id":dev,"bin_country":bincc,"is_card_present":cp,"created_at":ts(minute)})
    return t
def label(t,ftype,minute,src): labels.append({"transaction_id":t,"is_confirmed_fraud":True,"fraud_type":ftype,"labeled_at":ts(minute),"label_source":src})

# ---- Normal baseline: small per-account spend across normal merchants ----
for a in accounts:
    for _ in range(random.randint(2,6)):
        m=random.randint(0,40000); amt=round(random.uniform(5,300),2)
        res="APPROVED" if random.random()>0.08 else "DECLINED"
        reason="" if res=="APPROVED" else random.choice(["INSUFFICIENT_FUNDS","DO_NOT_HONOR"])
        newtxn(a["account_id"],m,amt,res,reason,f"10.0.{random.randint(0,255)}.{random.randint(1,254)}",
               f"dev_{a['account_id']}",f"MERCH{random.randint(1,8):03d}",random.choice(mccs),card(a["account_id"]+"main"),a["country"])

# ---- High-volume NORMAL merchants (low decline) -> stable population stats ----
normal_merchants=["MERCH001","MERCH002","MERCH003","MERCH011","MERCH012","MERCH013","MERCH014","MERCH015"]
for mi,mid in enumerate(normal_merchants):
    day_start=(mi+2)*2880  # each merchant gets its own day -> high-volume merchant-day
    for k in range(60):
        acc=f"ACC{random.randint(1,40):04d}"
        res="APPROVED" if random.random()>0.07 else "DECLINED"
        reason="" if res=="APPROVED" else "INSUFFICIENT_FUNDS"
        newtxn(acc,day_start+random.randint(0,1400),round(random.uniform(10,250),2),res,reason,
               f"10.2.{int(acc[3:])%256}.{int(acc[3:])}",f"dev_{acc}",mid,"GROCERY",card(acc+"main"),"US")

# ---- Pattern 1: CARD TESTING velocity ----
for ring in range(2):
    acc=f"ACC{random.randint(1,40):04d}"
    ip=f"45.66.{ring}.{random.randint(1,254)}"; dev=f"dev_tester_{ring}"; start=5000+ring*1000
    for k in range(25):
        res="DECLINED" if random.random()>0.2 else "APPROVED"
        reason="CVV_FAIL" if res=="DECLINED" else ""
        t=newtxn(acc,start+k*0.5,round(random.uniform(0.5,3.0),2),res,reason,ip,dev,"MERCH999","DIGITAL_GOODS",card(f"ring{ring}card{k}"),"US")
        label(t,"CARD_TESTING",start+200,"RULE")

# ---- Pattern 2: ATO (prior history clean; attack from new country/device) ----
for k in range(3):
    a=accounts[k]; acc=a["account_id"]
    a["country"]="US"  # pin home country
    for j in range(3):  # clean prior successful logins from home
        lid+=1; logins.append({"login_id":f"LG{lid:05d}","account_id":acc,"ip_address":f"10.0.0.{k}",
            "device_id":f"dev_{acc}","country":"US","login_result":"SUCCESS","created_at":ts(100+j*50)})
    fm=20000+k*100
    for _ in range(4):
        lid+=1; logins.append({"login_id":f"LG{lid:05d}","account_id":acc,"ip_address":"203.0.113.7",
            "device_id":"dev_attacker","country":"NG","login_result":"FAILURE","created_at":ts(fm)}); fm+=1
    lid+=1; logins.append({"login_id":f"LG{lid:05d}","account_id":acc,"ip_address":"203.0.113.7",
        "device_id":"dev_attacker","country":"NG","login_result":"SUCCESS","created_at":ts(fm)})
    t=newtxn(acc,fm+5,round(random.uniform(900,2500),2),"APPROVED","","203.0.113.7","dev_attacker","MERCH777","ELECTRONICS",card(acc+"main"),"US")
    label(t,"ATO",fm+300,"MANUAL_REVIEW")

# ---- Pattern 3: MERCHANT ABUSE (high decline-rate conduit merchant) ----
absm=30000
for k in range(45):
    acc=f"ACC{random.randint(1,40):04d}"
    res="DECLINED" if random.random()>0.25 else "APPROVED"  # ~75% decline
    reason="DO_NOT_HONOR" if res=="DECLINED" else ""
    t=newtxn(acc,absm+k,round(random.uniform(50,400),2),res,reason,f"77.88.{k%5}.{random.randint(1,254)}",f"dev_{acc}","MERCH_ABUSE","GAMING",card(acc+"main"),"US")
    if res=="DECLINED": label(t,"ABUSE",absm+400,"MANUAL_REVIEW")

# ---- Pattern 4: ANOMALOUS CLUSTER (shared device across many accounts) ----
shared="dev_shared_cluster"
for k in range(12):
    acc=f"ACC{random.randint(1,40):04d}"
    t=newtxn(acc,15000+k*2,round(random.uniform(100,600),2),"APPROVED","","62.210.9.5",shared,"MERCH555","TRAVEL",card(f"cluster{k}"),"GB")
    label(t,"OTHER",15500,"MANUAL_REVIEW")

# ---- Pattern 5: HIGH-RISK VELOCITY bust-out (one account, burst of big approved txns) ----
for ring in range(2):
    a=accounts[20+ring]; acc=a["account_id"]; a["is_high_risk_segment"]=True; a["kyc_status"]="PENDING"
    # small baseline first so avg stays modest
    for j in range(2): newtxn(acc,200+j*10,round(random.uniform(10,40),2),"APPROVED","",f"10.0.9.{ring}",f"dev_{acc}","MERCH004","GROCERY",card(acc+"main"),a["country"])
    bm=35000+ring*500
    for j in range(8):
        t=newtxn(acc,bm+j*5,round(random.uniform(400,900),2),"APPROVED","",f"10.0.9.{ring}",f"dev_{acc}","MERCH888","ELECTRONICS",card(acc+"main"),a["country"])
        label(t,"OTHER",bm+200,"MANUAL_REVIEW")

# ---- FP bait: legit single high-value purchases (NOT fraud) ----
for k in range(5):
    a=accounts[30+k]
    newtxn(a["account_id"],25000+k*50,round(random.uniform(900,1800),2),"APPROVED","",f"10.0.5.{k}",f"dev_{a['account_id']}","MERCH010","ELECTRONICS",card(a["account_id"]+"main"),a["country"])

def write(name,rows,fields):
    with open(f"{OUT}/{name}","w",newline="") as f:
        w=csv.DictWriter(f,fieldnames=fields); w.writeheader()
        for r in rows: w.writerow(r)
write("sample_accounts.csv",accounts,["account_id","email","country","account_created_at","kyc_status","is_high_risk_segment"])
write("sample_transactions.csv",txns,["transaction_id","account_id","card_fingerprint","merchant_id","merchant_category","transaction_amount","currency","auth_result","decline_reason","ip_address","device_id","bin_country","is_card_present","created_at"])
write("sample_login_events.csv",logins,["login_id","account_id","ip_address","device_id","country","login_result","created_at"])
write("sample_labels.csv",labels,["transaction_id","is_confirmed_fraud","fraud_type","labeled_at","label_source"])
print("accounts",len(accounts),"txns",len(txns),"logins",len(logins),"labels",len(labels))
