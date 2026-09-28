// v0.5 — Haptic-first experience. Reuses the complete v0.4.1 data/interaction engine.
// All output percentages describe the requested model, never measured motor output.
icons.settings='M9 3h6l1 3 3 1 2 5-2 5-3 1-1 3H9l-1-3-3-1-2-5 2-5 3-1ZM15.5 12a3.5 3.5 0 1 1-7 0 3.5 3.5 0 0 1 7 0';
icons.touch='M9 11V5a2 2 0 0 1 4 0v7M13 9a2 2 0 0 1 4 0v4M17 11a2 2 0 0 1 4 0v5c0 4-3 6-6 6h-3c-2 0-3-1-4-3l-4-5c-2-3 0-5 2-3l3 2';
icons.haptic='M8 3h8v18H8ZM11 18h2M4 7c-2 2-2 8 0 10M20 7c2 2 2 8 0 10';
icons.power='M12 2v10M6 5a9 9 0 1 0 12 0';
SCREENS.push(['manual','S46','手动震动控制','触感','由指尖掌握。','按住即动、松手即停 / 连续控制 → 调强度 → 随时停止']);
SCREENS.push(['methods','S47','全部震动方式','触感','不同方式，同一种掌控。','预设 / 手动 / 音乐跟随 / 组合 / 呼吸 / 远控']);
const screenOverrides={
 launch:['震动按摩，从这里开始。','开屏先说明用途 → 无需选歌即可使用'],
 home:['触感，握在自己手中。','选择震动模式 → 调强度 → 开始震动 → 定时停止'],
 focus:['只保留此刻的触感。','专注震动控制 → 防误触 → 随时停止'],
 library:['选择想要的震感。','16种震动模式 → 看节奏结构 → 调节 / 使用'],
 detail:['先了解，再感受。','输出与间隔 → 短时预览 → 使用并开始震动'],
 music:['让音乐驱动触感。','音乐作为震动来源 → 选歌 → 分析 → 同步震动'],
 musicplayer:['控制触感，音乐随行。','触觉输出优先 → 强度与映射 → 音源辅助控制'],
 studio:['亲手编排一种触感。','分段 / 曲线 / 敲击 / XY → 保存 → 作为震动模式使用'],
 manual:['按下，感受；松开，停下。','手动触感控制 → 无音乐依赖 → 随时停止'],
 methods:['完整能力，清晰主次。','每项功能都围绕手机触觉，所有原有流程保留']
};
for(const s of SCREENS){if(screenOverrides[s[0]])[s[4],s[5]]=screenOverrides[s[0]];if(s[3]==='播放')s[3]='触感';if(s[3]==='音乐')s[3]='音乐跟随震动';}
SCREENS.find(x=>x[0]==='focus')[2]='专注震动';
SCREENS.find(x=>x[0]==='library')[2]='震动模式库';
SCREENS.find(x=>x[0]==='musicplayer')[2]='音乐跟随震动控制';
SCREENS.find(x=>x[0]==='music')[2]='音乐跟随震动入口';
S.homeSource='pattern';
S.manual={mode:'hold',pointer:null,holding:false,started:0};

function hapticChannel(){
 if(S.music.playing)return 'music';
 if(S.session?.playing)return S.session.kind==='manual'?'manual':'pattern';
 if(S.homeSource==='music'&&S.music.buffer)return 'music';
 return S.session?.kind==='manual'?'manual':'pattern';
}
function hapticRunning(){return hapticChannel()==='music'?S.music.playing:!!S.session?.playing;}
function hapticPaused(){return hapticChannel()==='music'?S.music.offset>0:!!S.session&&!S.session.playing;}
function patternType(p){return p.id==='p01'?'连续震动':p.mode==='curve'||p.category==='渐变'?'渐变震动':p.category==='节奏'?'节奏轻点':'间歇震动';}
function structuralDescription(p){
 if(p.mode==='curve')return '强度沿曲线变化 · '+sec(patternLength(p))+'一轮';
 const e=p.segments?.[0];if(!e)return '自定义震动模式';
 if(p.id==='p01')return '持续、均匀的触感，无节拍间隔';
 if(p.id==='p02')return '震动 0.3 秒，停歇 0.5 秒，循环交替';
 return `${patternType(p)} · ${p.segments.length}个片段 · ${sec(patternLength(p))}一轮`;
}
function pulseMark(p,wide=false){
 const data=values(p,wide?60:28);
 return `<svg class="pulse-mark ${wide?'wide':''}" viewBox="0 0 ${data.length*5} 38" role="img" aria-label="模式请求强度与停顿示意"><path d="M0 33H${data.length*5}" stroke="var(--line)" stroke-width=".6"/>${data.map((v,i)=>`<rect x="${i*5+1}" y="${33-v*28}" width="2.4" height="${Math.max(1,v*28)}" rx="1.2" fill="${v?'var(--accent)':'var(--line)'}" opacity="${v?.8:.5}"/>`).join('')}</svg>`;
}
function hapticField(size='normal',staticView=false){
 return `<div class="haptic-field ${size}" ${staticView?'':'data-haptic-field'}>
 <div class="haptic-wash"></div><i class="touch-orbit orbit-a"></i><i class="touch-orbit orbit-b"></i><i class="touch-orbit orbit-c"></i>
 <div class="haptic-emblem">${ic('haptic')}</div>
 <span class="field-note">${staticView?'手机触觉 · 强弱可调':'手机触感 · 可视模拟'}</span>
 </div>`;
}
function outputReadout(){return `<div class="haptic-output"><span><i data-haptic-lamp></i><span data-haptic-status>尚未开始</span></span><span>请求强度 <b data-haptic-level>0</b><small>%</small></span></div>`;}
function safeTimerChip(){const special=S.session?.kind==='routine'?'routines':S.session?.kind==='breath'?'breath':null;
 return `<button class="time-chip" data-action="${special?'nav':'sheet'}" data-value="${special||'timer'}" aria-label="${special?'查看当前会话编排':'设置定时停止'}">${ic('clock')}<span><small>${S.session?'剩余':'定时停止'}</small><b data-live="remaining">${fmt(S.session?.remaining??store.timer)}</b></span>${ic('down')}</button>`;
}
function sourceName(){let c=hapticChannel();return c==='music'?'音乐跟随':c==='manual'?'手动控制':S.session?.kind==='routine'?'组合震动':S.session?.kind==='breath'?'呼吸轻触':'预设震动';}
function hapticCurrent(){const c=hapticChannel(),p=activePattern();return `<div class="current-haptic">
 <button class="current-pattern-button" data-action="${c==='music'?'nav':c==='manual'?'nav':'sheet'}" data-value="${c==='music'?'musicplayer':c==='manual'?'manual':'hapticPatterns'}">
 <span class="tiny muted">当前 · ${sourceName()}</span><strong>${esc(c==='music'?S.music.name:c==='manual'?'指尖控制':p.name)}</strong>
 <span class="small muted">${c==='music'?'音乐驱动触感变化':c==='manual'?'按压与强度由你控制':patternType(p)+' · '+sec(patternLength(p))+' / 轮'}</span></button>
 ${c==='pattern'?pulseMark(p):ic(c==='music'?'haptic':'touch')}<button class="text-btn" data-action="sheet" data-value="hapticPatterns" aria-label="更换震动模式">更换</button></div>`;}
function mainStrength(){const c=hapticChannel(),key=c==='music'?'m_gain':'gain',val=c==='music'?S.music.config.gain:store.gain;
 return `<div class="strength-control"><div class="range-label"><label for="r-${key}">震动强度</label><output id="o-${key}">${val}%</output></div><input type="range" id="r-${key}" data-bind="${key}" data-unit="%" min="0" max="100" step="1" value="${val}" aria-label="震动强度" ${S.guard?'disabled':''}><div class="range-help"><span>轻</span><span>相对强度，受设备限制</span><span>强</span></div></div>`;
}
VIEWS.launch=()=>`<section class="splash haptic-splash"><div class="caps">PERSONAL HAPTIC CARE</div><div><div class="splash-art">${art(theme().art)}</div><div class="logo">Pulse <em>Loom</em></div><h2>个人震动与触感</h2><p>选择一种震感，调成自己的轻重。<br>无需音乐，也能独立使用。</p></div><div class="splash-foot">${btn('进入震动首页 '+ic('arrow'),'enter')}${btn('首次使用 · 了解触感','nav','onboard','ghost')}<div class="tiny muted">交互原型 v0.5 · 震动以动画模拟<br>无实际马达输出或扣费</div></div></section>`;
VIEWS.onboard=()=>page(`${top('初次使用')}<div class="welcome-art">${art(S.onboardStep?'orb':'flower')}</div><div class="caps">${S.onboardStep?'YOUR TOUCH, YOUR CHOICE':'HAPTICS FIRST'}</div><h1 style="margin:14px 0">${S.onboardStep?'轻重、快慢，都由你。':'打开，就能选择震感。'}</h1><p class="lead" style="margin:15px 0">${S.onboardStep?'从预设、手动、音乐跟随或自己的编排中选择。每一种方式都有强度控制和停止入口；音乐是可选的触觉驱动来源。':'这是一款个人震动与触感工具。选择预设，再点击“开始震动”；不需要导入歌曲，也不需要录制音频。'}</p>${notice('当前为网页交互模型，震动用动画示意。音乐模块会在你主动开启后播放声音；其余预设独立运行。')}<div class="onboard-steps"><i class="${!S.onboardStep?'active':''}"></i><i class="${S.onboardStep?'active':''}"></i></div>${btn(S.onboardStep?'选择偏好':'继续','onboardNext')}${btn('跳过介绍，进入震动首页','finishOnboard','','ghost')}`);
VIEWS.home=()=>{const c=hapticChannel(),p=activePattern();return `<div class="page haptic-home">
 <header class="home-top"><div class="logo">Pulse Loom</div><div class="row">${ib('leaf','nav','themes','主题与深浅色')}${ib('settings','nav','settings','设置')}</div></header>
 <div class="home-intro"><div><div class="caps">YOUR PERSONAL HAPTIC SPACE</div><h1>震动按摩</h1><p>一点轻触，留给自己。</p></div><div class="intro-flower">${art(theme().art)}</div></div>
 ${hapticField()}${outputReadout()}${hapticCurrent()}
 ${mainStrength()}
 <div class="haptic-adjust-row">${c==='music'?`<button class="time-chip" data-action="nav" data-value="musicplayer">${ic('haptic')}<span><small>驱动方式</small><b>音乐跟随</b></span>${ic('arrow')}</button>`:safeTimerChip()}
 <button class="texture-chip" data-action="${c==='music'?'nav':'sheet'}" data-value="${c==='music'?'musicplayer':'adjust'}">${ic('sliders')}<span>${c==='music'?'灵敏度 · 质感':`${store.speed}× · ${store.sharp<34?'柔和':store.sharp<67?'均衡':'清晰'}`}<small>调节震感</small></span>${ic('arrow')}</button></div>
 <div class="home-mode-section">${section('常用震动模式','nav','全部模式','library')}<div class="haptic-quick-row">${['p01','p02','p04'].map(id=>{let q=pattern(id);return `<button class="haptic-quick ${c==='pattern'&&p.id===id?'selected':''}" data-action="quickPattern" data-value="${id}">${pulseMark(q)}<span>${q.name}</span><small>${q.id==='p01'?'连续':q.id==='p02'?'间歇':'起伏'}</small></button>`}).join('')}</div></div>
 ${section('换一种震动方式','nav','全部方式','methods')}<div class="method-shortcuts"><button data-action="nav" data-value="manual">${ic('touch')}<span>手动控制</span><small>按住感受，松手停</small></button><button data-action="nav" data-value="music">${ic('haptic')}<span>音乐跟随</span><small>由音乐驱动震动</small></button><button data-action="nav" data-value="studio">${ic('edit')}<span>自定义</span><small>编排自己的震感</small></button></div>
 <div class="home-secondary-links">${btn('组合体验','nav','routines','ghost')}${btn('专注震动','nav','focus','ghost')}</div>${S.output!=='ok'?notice('当前触觉故障为模拟状态。可进入设置排查，不通过付费解决。','warn'):''}
 </div>`;};
VIEWS.focus=()=>page(`${top('专注震动',ib('lock','touchGuard','','防误触',S.guard?'selected':''))}<div class="caps">PERSONAL HAPTIC CARE</div><h1 class="focus-title">只留此刻的触感。</h1>${hapticField('large')}${outputReadout()}${hapticCurrent()}${S.guard?notice('防误触已开启，模式和强度暂时锁定。下方停止始终可用。'):mainStrength()}<div class="haptic-adjust-row">${safeTimerChip()}<button class="texture-chip" data-action="${S.guard?'touchGuard':'sheet'}" data-value="adjust">${ic(S.guard?'unlock':'sliders')}<span>${S.guard?'解除防误触':'调整震感'}</span></button></div><div class="gap"></div>${btn('可选：搭配背景声景','nav','sounds','ghost')}`);
VIEWS.library=()=>page(`${heading('震动模式','HAPTIC PATTERNS · 不需要音乐','nav','studio','plus')}<div class="search">${ic('search')}<input id="patternSearch" data-bind="search" type="text" value="${esc(S.search)}" placeholder="搜索震感、模式或名称" aria-label="搜索震动模式"></div><div class="chips">${['全部','基础','轻柔','节奏','渐变','免费','已收藏'].map(c=>`<button class="chip ${S.category===c?'active':''}" data-action="category" data-value="${c}">${c}</button>`).join('')}</div><div id="libraryResults">${libraryResults()}</div><div class="gap"></div>${btn('全部震动方式 · 手动 / 音乐跟随 / 组合','nav','methods','outline')}${btn('从文件导入震动模式','importPattern','','ghost')}`);
patternRow=function(p,kind='normal'){return `<div class="list-row haptic-pattern-row"><div class="pattern-signature">${pulseMark(p)}</div><button class="list-link" data-action="detail" data-value="${p.id}"><h4>${esc(p.name)} ${p.premium?'<span class="badge pro">Pro</span>':''}</h4><p>${patternType(p)} · ${sec(patternLength(p))}/轮</p></button>${kind==='saved'?ib('dots','manage',p.id,'管理'+p.name):ib('heart','favorite',p.id,'收藏'+p.name,store.favorites.includes(p.id)?'selected':'')}</div>`;};
libraryResults=function(){let a=PRESETS.filter(p=>(S.category==='全部'||p.category===S.category||S.category==='免费'&&!p.premium||S.category==='已收藏'&&store.favorites.includes(p.id))&&(!S.search||[p.name,p.en,p.category].join(' ').toLowerCase().includes(S.search.toLowerCase())));if(!a.length)return empty('没有找到对应震感。','换一个名称或清除筛选。','clearSearch','','清除筛选');return `${!S.search&&S.category==='全部'?`<div class="pattern-compare">${['p01','p02'].map(id=>{let p=pattern(id);return `<button data-action="detail" data-value="${id}"><span class="caps">${id==='p01'?'STEADY':'PULSE'}</span><h3>${id==='p01'?'持续轻触':'柔和脉冲'}</h3>${pulseMark(p,true)}<p>${id==='p01'?'均匀输出，无间隔':'震动与停歇交替'}</p></button>`}).join('')}</div>`:''}${section('震动模式 · '+a.length)}${a.map(p=>patternRow(p)).join('')}`;};
VIEWS.detail=()=>{let p=pattern(S.detail),isPreview=S.session?.kind==='preview'&&S.session.pattern.id===p.id;return page(`${top('震动模式详情',ib('heart','favorite',p.id,'收藏',store.favorites.includes(p.id)?'selected':'')+ib('dots','manage',p.id,'更多'))}<div class="haptic-detail-heading"><div><div class="caps">${p.premium?'PRO HAPTIC PATTERN':'HAPTIC PATTERN'}</div><h1>${esc(p.name)}</h1><p>${esc(p.en||'Custom touch')} · ${patternType(p)}</p></div><div class="detail-flower">${art(p.art||'flower')}</div></div><p class="lead" style="margin:18px 0">${structuralDescription(p)}</p><div class="pattern-diagram"><div class="row between"><span>一轮震动怎样变化</span><small>设计参数</small></div>${pulseMark(p,true)}<div class="range-help"><span>0 秒</span><span>${sec(patternLength(p))}</span></div><p>竖线表示请求强度，空白表示间隔。</p></div><div class="key-stats"><div><strong>${(patternLength(p)/1000).toFixed(1)}s</strong><small>每轮长度</small></div><div><strong>${p.mode==='curve'?p.nodes.length:p.segments.length}</strong><small>${p.mode==='curve'?'曲线节点':'震动片段'}</small></div><div><strong>${p.premium?'Pro':'Free'}</strong><small>内容权限</small></div></div>${drawWave(p)}<div class="two">${btn(isPreview?'停止预览':'预览震感 · '+Math.min(8,patternLength(p)/1000)+'秒','preview',p.id,'secondary')}${btn('使用并开始震动','usePattern',p.id)}</div><div class="gap"></div>${btn('调节震感 · 强度 / 速度 / 质感','detailAdjust',p.id,'outline')}<div class="two" style="margin-top:12px">${btn('复制后编辑','editPattern',p.id,'ghost')}${btn('导出震动模式','exportPattern',p.id,'ghost')}</div>${notice('无需歌曲即可运行。此处仅模拟震动请求，不会发声或驱动马达。')}`);};

VIEWS.methods=()=>page(`${top('全部震动方式')}<div class="caps">ONE HAPTIC SPACE</div><h1 style="margin:12px 0">用喜欢的方式感受。</h1><p class="lead" style="margin-top:13px">入口围绕触感组织，完整能力都保留在这里。</p><div class="stack">${[
 ['library','haptic','预设震动','16种连续、间歇与渐变模式；无需音乐。'],['manual','touch','手动控制','按住感受、松手即停，或连续调节。'],['music','music','音乐跟随震动','选择自己的音乐，以能量或重拍驱动震动。'],['studio','edit','自定义震动','分段、曲线、敲击录制与XY编排。'],['routines','list','组合震动体验','把多个模式按顺序组成一次体验。'],['breath','breath','呼吸轻触与声景','可选的触觉节奏引导与背景声音。'],['remote','link','远程触感','双方授权、上限和紧急停止，全流程模拟。'],['watch','watch','Watch 控制','配对与触觉控制的本机模拟。']
 ].map(([r,i,t,d])=>`<button class="source-option" data-action="nav" data-value="${r}">${ic(i)}<div class="grow"><h3>${t}</h3><p>${d}</p></div>${ic('arrow')}</button>`).join('')}</div>`);
VIEWS.manual=()=>page(`${top('手动震动控制')}<div class="caps">TOUCH & RELEASE</div><h1 style="margin:10px 0">轻重随你，松手即停。</h1><p class="lead" style="margin:10px 0 17px">不录音、不选歌，专注一次触碰。</p>${seg([['hold','按住感受'],['continuous','连续控制']],S.manual.mode,'manualMode')}${hapticField('large')}${outputReadout()}${mainStrength()}<div class="haptic-adjust-row">${safeTimerChip()}<button class="texture-chip" data-action="sheet" data-value="adjust">${ic('sliders')}<span>触感质地<small>柔和 → 清晰</small></span>${ic('arrow')}</button></div><div class="gap"></div>${notice(S.manual.mode==='hold'?'按住下方按钮开始，松手或移出按钮即暂停。单次按压最多10秒；键盘可按住空格。':'点击下方开始后持续输出，随时暂停或停止；会话仍受定时限制。')}<div class="gap"></div>${btn('想保存变化？进入 XY 手势创作','newDraft','xy','ghost')}`);

VIEWS.music=()=>page(`${top('音乐跟随震动',ib('heart','nav','musicmixes','已保存跟随配置'))}<div class="caps">MUSIC-DRIVEN HAPTICS</div><h1 style="margin:13px 0">让音乐，带动触感。</h1><p class="lead" style="margin:12px 0 21px">音乐提供节奏，震动是体验主体。可调强度、跟随灵敏度与触感质地。</p><div class="source-flow"><span>${ic('music')}选一首音乐</span><b>→</b><span>${ic('sliders')}提取节奏</span><b>→</b><span>${ic('haptic')}跟随震动</span></div><div class="gap"></div>${btn('选择驱动音乐','nav','sources')}${S.music.buffer?`<div class="gap"></div>${btn('继续跟随：'+esc(S.music.name),'nav','musicplayer','outline')}`:''}${section('体验音乐驱动的震感')}<div class="stack">${[['petals','清晰重拍示例','Petal Steps · 原创合成 · 48秒'],['mist','柔和起伏示例','Mist Waltz · 原创合成 · 48秒']].map(([id,t,d])=>`<button class="source-option" data-action="demoMusic" data-value="${id}">${ic('haptic')}<div class="grow"><h3>${t}</h3><p>${d}</p></div>${ic('arrow')}</button>`).join('')}</div>${section('保存与再使用')}${linkrow('跟随配置','保留强度、映射、时间偏移与叠加预设','heart','nav','musicmixes')}${btn('返回独立震动 · 不需要音乐','nav','home','ghost')}${notice('音频可真实读取并播放，震动仅用动画模拟。使用本地文件，不读取其他App声音，不绕过受保护曲目。')}`);
VIEWS.musicplayer=()=>{const m=S.music;if(!m.buffer)return page(`${top('音乐跟随震动')}${empty('先选择驱动音乐。','本地文件或原创合成示例均可使用。','nav','sources','选择音乐')}`);return page(`${top('音乐跟随震动',ib('heart','saveMix','','保存跟随配置'))}<div class="caps">HAPTIC OUTPUT FIRST</div><h1 style="margin:10px 0 4px">由音乐驱动的触感</h1><p class="small muted">调整震动强弱，音乐保留自己的声音。</p>${hapticField('compact')}${outputReadout()}<div class="music-source-strip">${ic('music')}<div class="grow"><span class="tiny muted">当前驱动音乐</span><strong>${esc(m.name)}</strong></div><button class="text-btn" data-action="nav" data-value="sources">更换</button></div><div class="gap"></div>${seg([['energy','跟随起伏'],['beats','跟随重拍'],['blend','预设叠加']],m.config.mapping,'musicMapping')}${slider('震动强度','m_gain',m.config.gain)}${slider('跟随灵敏度','m_sensitivity',m.config.sensitivity)}<div class="field"><label>触感质地</label>${seg([['smooth','柔和'],['pulse','脉冲'],['crisp','清晰']],m.config.texture,'musicTexture')}</div>${m.config.mapping==='blend'?`<div class="field"><label for="overlay">叠加震动模式</label><select id="overlay" data-bind="musicOverlay">${PRESETS.map(p=>`<option value="${p.id}" ${m.config.overlay===p.id?'selected':''}>${p.name}</option>`).join('')}</select></div>${slider('预设混合比例','m_overlayMix',m.config.overlayMix)}`:''}<details class="source-details"><summary>音源与播放位置 <span data-live="musicPosition">${fmt(m.offset)}</span> / ${fmt(m.duration)}</summary>${musicWave()}<input type="range" min="0" max="${m.duration}" step=".1" value="${m.offset}" data-bind="musicSeek" id="musicSeek" aria-label="音乐播放进度">${slider('音乐音量','m_volume',m.config.volume)}${btn('同步时差 / 播放区间','sheet','musicAdvanced','outline')}</details><div class="gap"></div>${notice('上方请求强度由原型级音频能量与瞬态分析生成，未驱动马达；输出量也不是硬件测量。音乐音量可以调到0，保留视觉跟随。')}`);};
VIEWS.themepreview=()=>{let t=theme(S.themePreview);return page(`${top('主题预览')}<h1>${t.name} / ${t.cn}</h1><p class="small muted" style="margin:10px 0 18px">预览不覆盖当前主题，点击应用后保存。</p><div class="theme-preview haptic-theme-preview"><div class="caps">PERSONAL HAPTIC CARE</div><h2 style="margin-top:10px">震动按摩</h2>${hapticField('compact',true)}<div class="current-haptic"><div class="grow"><small class="muted">当前震动模式</small><h3>柔绽</h3></div>${pulseMark(pattern('p02'))}</div><div class="preview-controls"><span>${ic('power')}开始震动</span><span>${ic('stop')}停止</span></div></div><div class="swatch-dots">${palette(t.id).slice(0,6).map((c,i)=>`<i data-palette-chip="${i}" style="background:${c}"></i>`).join('')}</div>${btn(store.theme===t.id?'已应用 · 返回主题中心':'应用这套主题','applyTheme',t.id)}<div class="gap"></div>${btn('取消预览，保留原主题','cancelTheme','','ghost')}`);};

// A stable dock keeps explicit start/stop available on compact screens.
function renderHapticDock(){
 let el=$('#hapticDock');if(!el)return;
 if(!['home','focus','musicplayer','manual'].includes(S.route)){el.innerHTML='';el.hidden=true;return}
 el.hidden=false;let c=S.route==='musicplayer'?'music':hapticChannel();
 if(S.route==='manual')c='manual';
 const running=c==='music'?S.music.playing:!!S.session?.playing;
 const holding=S.route==='manual'&&S.manual.mode==='hold';
 let label=running?'暂停震动':hapticPaused()?'继续震动':'开始震动';
 if(c==='music')label=running?'暂停同步震动':S.music.buffer?'开始同步震动':'选择驱动音乐';
 if(holding)label=S.manual.holding?'松手即停':'按住感受';
 const action=S.route==='manual'?'manualContinuous':c==='music'?'musicPlay':'play';
 el.innerHTML=`<div class="haptic-dock-controls"><button class="haptic-start" ${holding?'data-manual-hold="true" id="manualHold"':`data-action="${action}"`} aria-label="${label}">${ic(holding?'touch':running?'pause':'power')}<span>${label}</span></button><button class="haptic-stop" data-action="stop" aria-label="立即停止所有输出">${ic('stop')}<span>停止</span></button></div><p>${c==='music'?'触觉为模拟 · 音频可发声':'触觉为可视模拟 · 无实际马达输出'}</p>`;
}
renderMini=function(){const active=S.session||S.music.playing||S.sound.active;
 if(!active||['launch','onboard','preferences','home','focus','musicplayer','manual','routineplayer','breathplayer','xy','capability'].includes(S.route)){$('#mini').innerHTML='';return;}
 const c=hapticChannel(),soundOnly=S.sound.active&&!S.session&&!S.music.playing,r=c==='music'?'musicplayer':S.session?.kind==='routine'?'routineplayer':S.session?.kind==='breath'?'breathplayer':c==='manual'?'manual':soundOnly?'sounds':'focus';
 const name=soundOnly?'背景声景':c==='music'?'音乐跟随震动':S.session?.title||'触觉会话';
 $('#mini').innerHTML=`<div class="mini-player haptic-mini">${ic(soundOnly?'volume':'haptic')}<button class="mini-name" data-action="nav" data-value="${r}"><b>${esc(name)}</b><span class="tiny">${soundOnly?'背景声音':hapticRunning()?'震动模拟中':'触觉已暂停'} · 点击返回</span></button>${ib('stop','stop','','立即停止所有输出','stop')}</div>`;
};
const originalRender=render;
render=function(){originalRender();
 const g={detail:'library',focus:'home',manual:'home',methods:'home',music:'home',sources:'home',musicauth:'home',analysis:'home',musicplayer:'home',musicmixes:'my',editor:'studio',curve:'studio',record:'studio',xy:'studio',routines:'home',routineedit:'studio',routineplayer:'home',breath:'home',breathplayer:'home',sounds:'home'};
 const sel=g[S.route]||(['home','library','studio'].includes(S.route)?S.route:'my');
 $('#tabs').innerHTML=[['home','haptic','触感'],['library','grid','模式'],['studio','edit','创作'],['my','user','我的']].map(([r,i,t])=>`<button data-action="nav" data-value="${r}" class="${sel===r?'active':''}" aria-label="${t}" ${sel===r?'aria-current="page"':''}>${ic(i)}<span>${t}</span></button>`).join('');
 $('#device').dataset.route=S.route;
 $('#prototypeLabel').textContent=`v0.5 · ${store.pro?'全功能模拟':'免费用户模拟'} · 审查地图`;
 renderHapticDock();updateHapticUI();
};
function requestedPatternLevel(){const s=S.session;if(!s?.playing)return 0;const p=s.pattern,cycle=patternLength(p)/1000;if(!cycle)return 0;let t=(elapsed(s)*store.speed)%cycle,v=0;
 if(p.mode==='curve')v=curveValue(p,t*1000);else{let phase=0;for(const e of p.segments||[]){if(t*1000>=phase&&t*1000<phase+e.duration){v=e.gain;break;}phase+=e.duration+e.gap;}}
 let level=v*s.gain/100,fi=(p.fadeIn||0)/1000,fo=(p.fadeOut||0)/1000;if(fi)level*=Math.min(1,elapsed(s)/fi);if(fo)level*=Math.min(1,s.remaining/fo);return clamp(level,0,1);
}
function updateHapticUI(){const c=hapticChannel(),running=hapticRunning(),level=c==='music'?(S.music.playing?mappedLevel():0):requestedPatternLevel();
 let text=S.output!=='ok'?'触觉已中断':running?'震动模拟中':hapticPaused()?'震动已暂停':'尚未开始震动';
 if(S.guard)text+=' · 防误触';
 $$('[data-haptic-status]').forEach(e=>e.textContent=text);$$('[data-haptic-level]').forEach(e=>e.textContent=Math.round(level*100));
 $$('[data-haptic-lamp]').forEach(e=>e.classList.toggle('active',running));
 $$('[data-haptic-field]').forEach(e=>{e.style.setProperty('--request-level',level.toFixed(3));e.classList.toggle('responding',running);e.classList.toggle('still',!!store.reduced||matchMedia('(prefers-reduced-motion:reduce)').matches);});
 const fields=[['gain',store.gain],['m_gain',S.music.config.gain]];for(const [k,v]of fields){const input=$('#r-'+k),o=$('#o-'+k);if(input&&document.activeElement!==input)input.value=v;if(o&&document.activeElement!==input)o.textContent=v+'%';}
}
const originalLive=updateLive;
updateLive=function(){originalLive();if(S.manual.holding&&!S.session?.playing)releaseManual();if(S.manual.holding&&performance.now()-S.manual.started>=10000){releaseManual('已达单次10秒，请松手后再试');}updateHapticUI();};

const originalPlay=ACTIONS.play;
ACTIONS.play=()=>{if(hapticChannel()==='music')return playMusic();return originalPlay();};
const originalStart=startSession;
startSession=function(p,kind='pattern',opts={}){pauseMusic();if(kind!=='preview')S.homeSource=kind==='manual'?'manual':'pattern';return originalStart(p,kind,opts);};
const originalMusic=playMusic;
playMusic=async function(){S.homeSource='music';return originalMusic();};
const originalSelect=selectPattern;
selectPattern=function(id){S.homeSource='pattern';return originalSelect(id);};
const originalQuick=ACTIONS.quickPattern;
ACTIONS.quickPattern=v=>{if(S.guard)return toast('防误触已开启');if(pattern(v).premium&&!store.pro)return originalQuick(v);pauseMusic();S.homeSource='pattern';return originalQuick(v);};
const originalDetailAdjust=ACTIONS.detailAdjust;
ACTIONS.detailAdjust=v=>{if(S.guard)return toast('防误触已开启');if(S.music.playing)pauseMusic();if(S.session&&S.session.kind!=='pattern')stopSession('选择预设');return originalDetailAdjust(v);};
ACTIONS.hapticPick=v=>{if(S.guard)return toast('先解除防误触');if(pattern(v).premium&&!store.pro)return gate('这个震动模式属于Pro。','可先短时预览，或切换完整审查体验。',()=>ACTIONS.hapticPick(v));closeSheet();ACTIONS.quickPattern(v);};
ACTIONS.manualMode=v=>{releaseManual();if(S.session?.kind==='manual')pauseSession();S.manual.mode=v;render();};
const manualPattern=()=>({id:'manual-direct',name:'手动触感',en:'Direct touch',category:'手动',mode:'basic',segments:[baseSeg(2000,0,1,store.sharp/100)],cycle:2000,loop:true,origin:'manual',premium:false});
function beginManual(pointer){if(S.manual.holding||S.guard||S.output!=='ok'){if(S.output!=='ok')showSheet('fault');return;}
 S.homeSource='manual';if(S.music.playing)pauseMusic();stopSound();
 if(S.session?.kind==='manual'&&S.session.remaining>0){if(!S.session.playing)resumeSession();}
 else startSession(manualPattern(),'manual');
 if(!S.session?.playing)return;
 S.manual.pointer=pointer;S.manual.holding=true;S.manual.started=performance.now();renderHapticDock();updateHapticUI();
}
function releaseManual(message=''){if(!S.manual.holding)return;S.manual.holding=false;S.manual.pointer=null;if(S.session?.kind==='manual')pauseSession();renderHapticDock();updateHapticUI();if(message)toast(message);}
ACTIONS.manualContinuous=()=>{if(S.manual.mode==='hold')return;if(S.session?.kind==='manual')resumeSession();else startSession(manualPattern(),'manual');};
const originalStop=stopAll;
stopAll=function(reason='手动停止',complete=false){S.manual.holding=false;S.manual.pointer=null;return originalStop(reason,complete);};
const originalPause=pauseAll;
pauseAll=function(reason='暂停',notify=true){releaseManual();return originalPause(reason,notify);};
const originalNav=nav;
nav=function(route,opts={}){if(S.route==='manual'&&route!=='manual'){releaseManual();if(S.session?.kind==='manual')pauseSession();}if(route==='manual'&&S.route!=='manual'){pauseAll('进入手动控制',false);S.homeSource='manual';}return originalNav(route,opts);};
ACTIONS.enter=()=>nav('home',{reset:true});
const originalReset=ACTIONS.resetPrototype;
ACTIONS.resetPrototype=()=>{originalReset();const run=confirmation?.run;if(run)confirmation.run=()=>{S.homeSource='pattern';S.manual={mode:'hold',holding:false,pointer:null,started:0};run();};};

const originalSheets=renderSheet;
renderSheet=function(){
 if(S.modal?.type==='hapticPatterns'){
 const body=`<p class="small muted" style="margin-bottom:12px">选择预设仅更换模式；运行中沿用剩余时间。无需歌曲。</p><div class="two">${btn('手动控制','nav','manual','outline')}${btn('音乐跟随震动','nav','music','outline')}</div><div class="picker-patterns">${PRESETS.map(p=>`<button class="picker-pattern ${activePattern().id===p.id?'selected':''}" data-action="hapticPick" data-value="${p.id}"><div class="grow"><b>${esc(p.name)}</b><small>${patternType(p)} · ${sec(patternLength(p))}/轮</small></div>${pulseMark(p)}<span class="badge">${p.premium?'Pro':'免费'}</span></button>`).join('')}</div>`;
 $('#modalRoot').innerHTML=`<div class="modal-shade" data-dismiss="true"><section class="sheet" role="dialog" aria-modal="true" aria-label="更换震动模式"><div class="sheet-handle"></div><div class="topbar"><h2>更换震动模式</h2>${ib('close','closeSheet','','关闭弹层')}</div>${body}</section></div>`;
 }else originalSheets();
 if(S.modal&&(S.session?.playing||S.music.playing||S.sound.active)){$('#modalRoot .sheet')?.insertAdjacentHTML('beforeend',`<div class="sheet-emergency">${btn(ic('stop')+' 立即停止所有输出','stop','','outline')}</div>`);}
};
// Shared controls remain safe when a tab or a source changes.
document.addEventListener('pointerdown',e=>{if(!e.target.closest('[data-manual-hold]')||e.button!==0)return;e.preventDefault();beginManual(e.pointerId);const pad=$('[data-manual-hold]');if(pad&&S.manual.holding){try{pad.setPointerCapture(e.pointerId)}catch(_){}}});
document.addEventListener('pointerup',e=>{if(S.manual.pointer===e.pointerId)releaseManual();});
document.addEventListener('pointercancel',e=>{if(S.manual.pointer===e.pointerId)releaseManual();});
document.addEventListener('pointermove',e=>{if(S.manual.pointer!==e.pointerId)return;const pad=$('[data-manual-hold]');if(!pad)return releaseManual();const b=pad.getBoundingClientRect();if(e.clientX<b.left||e.clientX>b.right||e.clientY<b.top||e.clientY>b.bottom)releaseManual();});
document.addEventListener('keydown',e=>{if(e.target.closest?.('[data-manual-hold]')&&[' ','Enter'].includes(e.key)&&!e.repeat){e.preventDefault();beginManual('keyboard');$('[data-manual-hold]')?.focus({preventScroll:true});}});
document.addEventListener('keyup',e=>{if(S.manual.pointer==='keyboard'&&[' ','Enter'].includes(e.key)){e.preventDefault();releaseManual();$('[data-manual-hold]')?.focus({preventScroll:true});}});
window.addEventListener('blur',()=>{releaseManual();});
document.addEventListener('lostpointercapture',e=>{if(e.target.id==='manualHold'&&S.manual.pointer===e.pointerId)releaseManual();});
// Source paths remain registered; the redesigned shell does not drop features.
