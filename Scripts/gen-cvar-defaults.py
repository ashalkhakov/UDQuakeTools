#!/usr/bin/env python3
# Regenerates Sources/Libraries/UDCommon/idCVarDefaults.inc from dhewm3's sources:
#   Scripts/gen-cvar-defaults.py Sources/Libraries/UDCommon/idCVarDefaults.inc [path/to/dhewm3/neo]
import re, os, sys
root = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), '../../older-projects/dhewm3/neo')
dirs = ['framework','renderer','sound','sys','ui','idlib','cm','game']
decl = re.compile(r'\bidCVar\s+([A-Za-z_][A-Za-z_0-9:]*)\s*\(', re.S)
def split_args(s):
    args=[];depth=0;cur='';i=0;inq=False
    while i < len(s):
        c=s[i]
        if inq:
            cur+=c
            if c=='\\': cur+=s[i+1]; i+=1
            elif c=='"': inq=False
        elif c=='"': inq=True; cur+=c
        elif c in '(<[': depth+=1; cur+=c
        elif c in ')>]': depth-=1; cur+=c
        elif c==',' and depth==0: args.append(cur.strip()); cur=''
        else: cur+=c
        i+=1
    if cur.strip(): args.append(cur.strip())
    return args
out = {}
skipped = []
for d in dirs:
    for dp, dn, fn in os.walk(os.path.join(root,d)):
        for f in fn:
            if not f.endswith('.cpp'): continue
            p=os.path.join(dp,f)
            t=open(p,encoding='latin-1').read()
            # strip comments
            t=re.sub(r'//[^\n]*','',t)
            t=re.sub(r'/\*.*?\*/','',t,flags=re.S)
            for m in decl.finditer(t):
                # find matching paren
                i=m.end(); depth=1; j=i; inq=False
                while j < len(t) and depth>0:
                    c=t[j]
                    if inq:
                        if c=='\\': j+=1
                        elif c=='"': inq=False
                    elif c=='"': inq=True
                    elif c=='(': depth+=1
                    elif c==')': depth-=1
                    j+=1
                args=split_args(t[i:j-1])
                if len(args)<3 or not args[0].startswith('"'): skipped.append((p,args[:2])); continue
                name=args[0].strip('"')
                default=args[1]
                macros = {
                    'imageFilter[1]': '"GL_LINEAR_MIPMAP_LINEAR"', '_in_kbdNames[0]': '"auto"',
                    'si_gameTypeArgs[ 0 ]': '"singleplayer"', 'ui_skinArgs[ 0 ]': '"skins/characters/player/marine_mp"',
                    'ui_teamArgs[ 0 ]': '"Red"', 'si_readyArgs[ 0 ]': '"Not Ready"', 'si_spectateArgs[ 0 ]': '"Play"',
                    'DEFAULT_GRAVITY_STRING': '"1066"', 'IDNET_HOST ":" IDNET_MASTER_PORT': '"idnet.ua-corp.com:27650"',
                    '0': '"0"',
                }
                if default in macros:
                    default = macros[default]
                if not default.startswith('"'):
                    skipped.append((p,name,default)); default='""'
                default=re.sub(r'"\s+"','',default) # "a" "b" concatenated
                flags=args[2]
                typ='s'
                if 'CVAR_BOOL' in flags: typ='b'
                elif 'CVAR_INTEGER' in flags: typ='i'
                elif 'CVAR_FLOAT' in flags: typ='f'
                vmin=vmax=None
                # forms: (name, value, flags, desc, valueMin, valueMax, ...) or (name,value,flags,desc,valueStrings,...)
                if len(args)>=6:
                    try:
                        vmin=float(args[4].rstrip('fF')); vmax=float(args[5].rstrip('fF'))
                    except ValueError: pass
                if name not in out:
                    out[name]=(default,typ,vmin,vmax,os.path.relpath(p,root))
print(len(out), file=sys.stderr)
for s in skipped: print('skip',s,file=sys.stderr)
with open(sys.argv[1],'w') as f:
    f.write('// Generated from dhewm3\'s idCVar declarations (framework, renderer, sound, sys, ui,\n// idlib, cm, game): every cvar the engine and the base game register, its\n// default, its type and its range. Do not edit; regenerate.\n')
    for name in sorted(out, key=str.lower):
        d,t,a,b,src=out[name]
        mn = repr(float(a)) if a is not None else '1.0'
        mx = repr(float(b)) if b is not None else '-1.0'
        f.write('{ "%s", %s, \'%s\', %sf, %sf },\n' % (name, d, t, mn, mx))
