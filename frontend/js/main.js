/**
 * ============================================================
 * main.js —— 系统主界面逻辑
 * 对接后端：小区/设施/分类查询、缓冲区分析、评价、收藏、方案、搜索、AI
 * 依赖：config.js（api/toast/TokenStore）、高德地图JS API 2.0
 * ============================================================
 */
 
// ---------- 全局状态 ----------
let map;                 // 高德地图实例
let communityMarkers = []; // 小区 marker
let facilityMarkers = [];  // 设施 marker
let communityLayer, facilityLayer;
let heatLayer = null, clusterGroup = null;
let overlayGroup = [];    // 缓冲区/框选等叠加物
let startPoint = null;    // 当前分析起点 {lng,lat,communityId}
let categories = [];     // 设施分类
let renderMode = 'scatter'; // scatter / heat
let satLayer = null;
 
// 设施分类 → 颜色与图标
const CAT_STYLE = {
    EDU:  { color:'#3b82f6', icon:'📖', name:'教育' },
    MED:  { color:'#ef4444', icon:'✚', name:'医疗' },
    MKT:  { color:'#f97316', icon:'🛒', name:'商超' },
    CUL:  { color:'#22c55e', icon:'🌳', name:'公园' },
    LIFE: { color:'#a855f7', icon:'🔧', name:'生活' },
    AGE:  { color:'#ec4899', icon:'👵', name:'养老' },
    TRA:  { color:'#06b6d4', icon:'🚌', name:'交通' }
};
function catStyle(code){ return CAT_STYLE[code] || { color:'#94a3b8', icon:'📍', name:code||'设施' }; }
 
// ---------- 初始化 ----------
window.onload = async function () {
    if (!requireLogin()) return;
    // 顶部用户信息
    const u = TokenStore.getUser();
    document.getElementById('userName').textContent = u.username;
    document.getElementById('avatar').textContent = u.username.charAt(0).toUpperCase();
    if (TokenStore.isAdmin()) document.getElementById('adminMenu').style.display = '';
 
    initMap();
    bindPanelEvents();
    await loadCategories();
    await Promise.all([loadCommunities(), loadFacilities()]);
};
 
// ---------- 1. 地图初始化 ----------
function initMap() {
    map = new AMap.Map('map', {
        zoom: MAP_ZOOM,
        center: MAP_CENTER,
        mapStyle: 'amap://styles/whitesmoke',
        viewMode: '2D'
    });
    map.addControl(new AMap.ToolBar({ position: { top: '100px', right: '10px' } }));
    map.addControl(new AMap.Scale());
 
    // 任意点模式：点击地图选起点
    map.on('click', e => {
        if (startMode === 'point') {
            setStartPoint(e.lnglat.getLng(), e.lnglat.getLat(), null);
        }
    });
}
 
// 底图切换
function switchBase(type) {
    document.getElementById('baseVector').className = type==='vector' ? 'on' : '';
    document.getElementById('baseSat').className = type==='sat' ? 'on' : '';
    if (type === 'sat') {
        if (!satLayer) satLayer = new AMap.TileLayer.Satellite();
        satLayer.setMap(map);
    } else if (satLayer) {
        satLayer.setMap(null);
    }
}
 
// ---------- 2. 加载分类 ----------
async function loadCategories() {
    try {
        categories = await api('/api/category/list');
        const box = document.getElementById('catBox');
        box.innerHTML = categories.map(c =>
            `<label class="ck-item"><input type="checkbox" value="${c.categoryCode}" checked>
             <span style="color:${catStyle(c.categoryCode).color}">${catStyle(c.categoryCode).icon}</span>
             ${c.categoryName}</label>`).join('');
    } catch (e) {}
}
 
// ---------- 3. 加载小区 ----------
async function loadCommunities() {
    showLoading(true);
    const list = await api('/api/community/list');
    communityMarkers = list.map(c => {
        const price = c.price ? Number(c.price) : 0;
        const color = price >= 12000 ? '#ef4444' : price >= 8000 ? '#f59e0b' : '#22c55e';
        const m = new AMap.Marker({
            position: [Number(c.longitude), Number(c.latitude)],
            content: `<div style="
                width:26px;height:26px;border-radius:50% 50% 50% 0;transform:rotate(-45deg);
                background:${color};border:2px solid #fff;box-shadow:0 2px 6px rgba(0,0,0,.3);
                display:flex;align-items:center;justify-content:center;color:#fff;font-size:12px;">🏠</div>`,
            offset: new AMap.Pixel(-13, -13)
        });
        m.on('click', () => {
            if (startMode === 'community') {
                setStartPoint(Number(c.longitude), Number(c.latitude), c.communityId);
            }
            openCommunityDetail(c);
        });
        m._data = c;
        return m;
    });
    renderMarkers();
    showLoading(false);
}
 
// ---------- 4. 加载设施 ----------
async function loadFacilities() {
    const list = await api('/api/facility/list');
    facilityMarkers = list.map(f => {
        const st = catStyle(f.categoryCode);
        const m = new AMap.Marker({
            position: [Number(f.longitude), Number(f.latitude)],
            content: `<div style="
                width:24px;height:24px;border-radius:50%;background:${st.color};
                border:2px solid #fff;box-shadow:0 2px 6px rgba(0,0,0,.25);
                display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;">${st.icon}</div>`,
            offset: new AMap.Pixel(-12, -12)
        });
        m.on('click', () => openFacilityDetail(f));
        m._data = f;
        return m;
    });
    renderMarkers();
}
 
// 根据当前渲染模式渲染 marker（散点/聚合/热力）
function renderMarkers() {
    // 先清旧
    communityMarkers.forEach(m => m.setMap(null));
    facilityMarkers.forEach(m => m.setMap(null));
    if (heatLayer) { heatLayer.setMap(null); heatLayer = null; }
    if (clusterGroup) { clusterGroup.setMap(null); clusterGroup = null; }
 
    if (renderMode === 'heat') {
        // 热力图（设施密度）
        const data = facilityMarkers.map(m => ({
            lng: Number(m._data.longitude), lat: Number(m._data.latitude), count: 1
        }));
        heatLayer = new AMap.HeatMap(map, {
            radius: 25, opacity: [0, 0.8],
            gradient: { 0.2:'#3b82f6', 0.4:'#06b6d4', 0.6:'#facc15', 0.8:'#f97316', 1:'#ef4444' }
        });
        heatLayer.setDataSet({ data, max: 10 });
        // 小区仍显示散点
        communityMarkers.forEach(m => m.setMap(map));
    } else {
        // 散点模式 + 点聚合
        communityMarkers.forEach(m => m.setMap(map));
        clusterGroup = new AMap.MarkerCluster(map, facilityMarkers, {
            gridSize: 60,
            renderClusterMarker: (ctx) => {
                const n = ctx.markers.length;
                ctx.marker.setContent(`<div style="width:${30+n*2}px;height:${30+n*2}px;line-height:${30+n*2}px;
                    text-align:center;border-radius:50%;background:linear-gradient(135deg,#1676d6,#2ec4b6);
                    color:#fff;font-size:13px;border:2px solid #fff;box-shadow:0 2px 8px rgba(0,0,0,.3)">${n}</div>`);
                ctx.marker.setOffset(new AMap.Pixel(-(15+n), -(15+n)));
            }
        });
    }
}
 
function setRenderMode(mode) {
    renderMode = mode;
    document.getElementById('modeScatter').className = mode==='scatter' ? 'on' : '';
    document.getElementById('modeHeat').className = mode==='heat' ? 'on' : '';
    renderMarkers();
}
 
// ---------- 5. 分析起点 ----------
let startMode = 'point';
function setStartMode(mode) {
    startMode = mode;
    document.getElementById('modePoint').className = mode==='point' ? 'chip on' : 'chip';
    document.getElementById('modeCommunity').className = mode==='community' ? 'chip on' : 'chip';
    toast(mode==='point' ? '请在地图空白处点击选起点' : '请点击地图上的小区点位作为起点');
}
 
function setStartPoint(lng, lat, communityId) {
    clearOverlays();
    startPoint = { lng, lat, communityId };
    const m = new AMap.Marker({
        position: [lng, lat],
        content: `<div style="position:relative;width:24px;height:24px;">
            <div style="position:absolute;inset:0;border-radius:50%;background:#2ec4b6;
                border:2px solid #fff;box-shadow:0 0 0 6px rgba(46,196,182,.25);"></div>
            <div style="position:absolute;inset:6px;border-radius:50%;background:#fff;
                animation:pulse 1.4s infinite;"></div></div>
            <style>@keyframes pulse{0%{transform:scale(.7);opacity:1}100%{transform:scale(1.6);opacity:0}}</style>`,
        offset: new AMap.Pixel(-12, -12)
    });
    m.setMap(map);
    overlayGroup.push(m);
    map.setCenter([lng, lat]);
    toast('起点已拾取');
}
 
// ---------- 6. 面板事件 ----------
function bindPanelEvents() {
    // 时间选择
    document.querySelectorAll('#timeOpts .chip').forEach(chip => {
        chip.onclick = () => {
            document.querySelectorAll('#timeOpts .chip').forEach(c => c.className='chip');
            chip.className = 'chip on';
        };
    });
    // 速度
    const speed = document.getElementById('speed');
    speed.oninput = () => document.getElementById('speedV').textContent = speed.value;
    // 房价
    const pmin = document.getElementById('priceMin'), pmax = document.getElementById('priceMax');
    pmin.oninput = () => document.getElementById('priceMinV').textContent = pmin.value;
    pmax.oninput = () => document.getElementById('priceMaxV').textContent = pmax.value;
    // 权重（简单联动，不强制和为100）
    [['wPrice','wPriceV'],['wAcc','wAccV'],['wEva','wEvaV']].forEach(([id, lab]) => {
        const el = document.getElementById(id);
        el.oninput = () => document.getElementById(lab).textContent = el.value;
    });
}
 
function currentTimeMin() {
    const on = document.querySelector('#timeOpts .chip.on');
    return on ? Number(on.dataset.t) : 15;
}
function selectedCategories() {
    return [...document.querySelectorAll('#catBox input:checked')].map(i => i.value);
}
 
// ---------- 7. 开始分析 ----------
async function runAnalysis() {
    if (!startPoint) { toast('请先选择分析起点'); return; }
    const speed = Number(document.getElementById('speed').value);
    const timeMin = currentTimeMin();
    const radius = Math.round(speed * timeMin); // 米
 
    showLoading(true);
    try {
        // 调用后端缓冲区设施查询
        const facilities = await api('/api/facility/buffer', {
            query: { lng: startPoint.lng, lat: startPoint.lat, radius }
        });
        // 画缓冲区
        const circle = new AMap.Circle({
            center: [startPoint.lng, startPoint.lat],
            radius,
            strokeColor: '#0e7490', strokeWeight: 2, fillColor: '#2ec4b6', fillOpacity: 0.18
        });
        circle.setMap(map);
        overlayGroup.push(circle);
 
        // 按勾选分类过滤
        const cats = selectedCategories();
        const filtered = facilities.filter(f => !cats.length || cats.includes(f.categoryCode));
 
        // 周边小区（同一缓冲区）
        const communities = await api('/api/community/buffer', {
            query: { lng: startPoint.lng, lat: startPoint.lat, radius }
        });
 
        renderResult(filtered, communities);
        map.setFitView([circle]);
    } catch (e) {
    }
    showLoading(false);
}
 
// 渲染右侧结果
function renderResult(facs, coms) {
    document.getElementById('kpiFac').textContent = facs.length;
    document.getElementById('kpiCom').textContent = coms.length;
    // 平均房价
    const prices = coms.map(c => Number(c.price)).filter(v => v > 0);
    const avgP = prices.length ? Math.round(prices.reduce((a,b)=>a+b,0)/prices.length) : 0;
    document.getElementById('kpiAvg').textContent = avgP ? avgP : '--';
    // 综合评分：设施评分均值
    const scores = facs.map(f => Number(f.avgScore)).filter(v => v > 0);
    const avgS = scores.length ? (scores.reduce((a,b)=>a+b,0)/scores.length).toFixed(1) : '--';
    document.getElementById('kpiScore').textContent = avgS;
 
    // 设施列表
    document.getElementById('facList').innerHTML = facs.length ? facs.map(f => `
        <li onclick="locate(${Number(f.longitude)},${Number(f.latitude)})">
            <b>${f.facilityName}</b> <span class="badge badge-ok">${f.categoryName||''}</span>
            <div class="sub">${f.distance?Math.round(f.distance)+' m · ':''}评分 ${f.avgScore||'--'}</div>
        </li>`).join('') : '<li class="empty">该范围内无勾选类设施</li>';
 
    // 小区列表
    document.getElementById('comList').innerHTML = coms.length ? coms.map(c => `
        <li onclick="openCommunityDetail(${JSON.stringify(c).replace(/"/g,'&quot;')})">
            <b>${c.communityName}</b>
            <div class="sub">${c.price?c.price+' 元/㎡ · ':''}评分 ${c.avgScore||'--'}</div>
        </li>`).join('') : '<li class="empty">该范围内无小区</li>';
}
 
function locate(lng, lat) {
    map.setZoomAndCenter(15, [lng, lat]);
}
 
// ---------- 8. 小区详情弹窗 ----------
async function openCommunityDetail(c) {
    if (typeof c === 'string') c = JSON.parse(c);
    let evalsHtml = '';
    try {
        // 该小区已通过评价
        const list = await api('/api/evaluation/list', { query: { status: 1 } });
        const mine = list.filter(e => e.objectType === 'community' && e.objectId === c.communityId);
        evalsHtml = mine.length ? mine.map(e => `
            <div class="eval-item">
                <span class="star">${'★'.repeat(Math.round(Number(e.score)))}${'☆'.repeat(5-Math.round(Number(e.score)))}</span>
                <div>${e.content||''}</div>
            </div>`).join('') : '<div class="empty">暂无公开评价</div>';
    } catch (e) {}
 
    setModal(`
        <h3>🏠 ${c.communityName}</h3>
        <div class="detail-row"><span>地址</span><b>${c.address||'--'}</b></div>
        <div class="detail-row"><span>房价</span><b>${c.price?c.price+' 元/㎡':'--'}</b></div>
        <div class="detail-row"><span>户数 / 人口</span><b>${c.houseCount||'-'} / ${c.population||'-'}</b></div>
        <div class="detail-row"><span>用户平均评分</span><b>${c.avgScore?Number(c.avgScore).toFixed(1):'--'}</b></div>
        <div class="detail-row"><span>所属街道</span><b>${c.districtName||'--'}</b></div>
        <div style="margin-top:12px;font-size:13px;font-weight:600">用户评价</div>
        <div id="evalBox">${evalsHtml}</div>
        <div class="field" style="margin-top:10px">
            <select id="myScore"><option value="5">★★★★★ 非常满意</option><option value="4">★★★★ 满意</option><option value="3">★★★ 一般</option><option value="2">★★ 较差</option><option value="1">★ 很差</option></select>
            <textarea id="myEval" rows="2" placeholder="写下你的评价（提交后待管理员审核）"></textarea>
        </div>
        <div style="display:flex;gap:8px">
            <button class="btn" onclick="submitEval('community',${c.communityId})">提交评价</button>
            <button class="btn btn-ghost" onclick="fav('community',${c.communityId})">☆ 收藏</button>
            <button class="btn btn-ghost" onclick="closeModal();setStartPoint(${Number(c.longitude)},${Number(c.latitude)},${c.communityId})">以此为起点分析</button>
        </div>
    `);
}
 
// ---------- 9. 设施详情弹窗 ----------
async function openFacilityDetail(f) {
    let aiHtml = '';
    try {
        const ai = await api('/api/ai/facilityScore/' + f.facilityId);
        aiHtml = `<div class="eval-item">🤖 ${ai.advice}（综合分 ${ai.score100} · ${ai.level}）</div>`;
    } catch (e) {}
 
    let evalsHtml = '';
    try {
        const list = await api('/api/evaluation/list', { query: { status: 1 } });
        const mine = list.filter(e => e.objectType === 'facility' && e.objectId === f.facilityId);
        evalsHtml = mine.length ? mine.map(e => `
            <div class="eval-item">
                <span class="star">${'★'.repeat(Math.round(Number(e.score)))}</span>
                <div>${e.content||''}</div>
            </div>`).join('') : '<div class="empty">暂无公开评价</div>';
    } catch (e) {}
 
    setModal(`
        <h3>${catStyle(f.categoryCode).icon} ${f.facilityName}</h3>
        <div class="detail-row"><span>分类</span><b>${f.categoryName||'--'}</b></div>
        <div class="detail-row"><span>地址</span><b>${f.address||'--'}</b></div>
        <div class="detail-row"><span>开放时间</span><b>${f.openTime||'--'}</b></div>
        <div class="detail-row"><span>联系电话</span><b>${f.phone||'--'}</b></div>
        <div class="detail-row"><span>用户评分</span><b>${f.avgScore?Number(f.avgScore).toFixed(1):'--'}</b></div>
        <div style="margin-top:10px">${aiHtml}</div>
        <div style="margin-top:8px;font-size:13px;font-weight:600">用户评价</div>
        <div>${evalsHtml}</div>
        <div class="field" style="margin-top:10px">
            <select id="myScore"><option value="5">★★★★★</option><option value="4">★★★★</option><option value="3">★★★</option><option value="2">★★</option><option value="1">★</option></select>
            <textarea id="myEval" rows="2" placeholder="写下评价（待审核后公开）"></textarea>
        </div>
        <div style="display:flex;gap:8px">
            <button class="btn" onclick="submitEval('facility',${f.facilityId})">提交评价</button>
            <button class="btn btn-ghost" onclick="fav('facility',${f.facilityId})">☆ 收藏</button>
        </div>
    `);
}
 
// 提交评价
async function submitEval(objectType, objectId) {
    const score = Number(document.getElementById('myScore').value);
    const content = document.getElementById('myEval').value.trim();
    try {
        await api('/api/evaluation/submit', {
            method: 'POST',
            body: { objectType, objectId, score, content }
        });
        toast('评价提交成功，等待管理员审核');
        closeModal();
    } catch (e) {}
}
 
// 收藏
async function fav(objectType, objectId) {
    const u = TokenStore.getUser();
    try {
        await api('/api/favorite/add', {
            method: 'POST',
            body: { userId: u.userId, objectType, objectId }
        });
        toast('已收藏 ⭐');
    } catch (e) {}
}
 
// ---------- 10. 全局搜索 ----------
async function doSearch() {
    const kw = document.getElementById('kw').value.trim();
    if (!kw) return;
    try {
        const data = await api('/api/search', { query: { keyword: kw } });
        if (data.communities.length) {
            const c = data.communities[0];
            map.setZoomAndCenter(15, [Number(c.longitude), Number(c.latitude)]);
            openCommunityDetail(c);
        } else if (data.facilities.length) {
            const f = data.facilities[0];
            map.setZoomAndCenter(15, [Number(f.longitude), Number(f.latitude)]);
            openFacilityDetail(f);
        } else {
            toast('未找到匹配结果');
        }
    } catch (e) {}
}
 
// ---------- 11. 框选查询 ----------
let boxMode = false;
function toggleBox() {
    boxMode = !boxMode;
    if (boxMode) {
        toast('请在地图上拖拽出矩形框选范围');
        map.on('mousemove', drawBox);
    }
}
let boxRect = null;
function drawBox(e) { /* 简化：点击两次确定对角 */ }
 
// ---------- 12. 工具 ----------
function resetView() {
    map.setZoomAndCenter(MAP_ZOOM, MAP_CENTER);
}
function measure() {
    const tool = new AMap.MouseTool(map);
    tool.rule();
    toast('沿地图点击测量距离，双击结束');
}
function clearOverlays() {
    overlayGroup.forEach(o => o.setMap(null));
    overlayGroup = [];
}
function clearAll() {
    clearOverlays();
    startPoint = null;
    document.getElementById('facList').innerHTML = '<li class="empty">尚未分析</li>';
    document.getElementById('comList').innerHTML = '<li class="empty">尚未分析</li>';
}
 
// ---------- 13. 我的收藏面板 ----------
async function openFav() {
    const u = TokenStore.getUser();
    const list = await api('/api/favorite/list', { query: { userId: u.userId } });
    setModal(`
        <h3>⭐ 我的收藏</h3>
        <div id="favBox">
            ${list.length ? list.map(f => `
                <div class="eval-item" style="display:flex;justify-content:space-between;align-items:center">
                    <div><b>${f.objectType==='community'?'小区':'设施'}</b> #${f.objectId}
                    <div class="sub">${f.remark||''} · ${f.createTime||''}</div></div>
                    <button class="btn btn-danger btn-sm" onclick="removeFav(${f.id})">取消</button>
                </div>`).join('') : '<div class="empty">还没有收藏，点击点位星星即可收藏</div>'}
        </div>
    `);
}
async function removeFav(id) {
    const u = TokenStore.getUser();
    // 从收藏列表里找到对应记录
    const list = await api('/api/favorite/list', { query: { userId: u.userId } });
    const f = list.find(x => x.id === id);
    if (!f) return;
    await api('/api/favorite/delete', {
        method: 'DELETE',
        query: { userId: u.userId, objectType: f.objectType, objectId: f.objectId }
    });
    toast('已取消收藏');
    openFav();
}
 
// ---------- 14. 保存分析方案 ----------
async function savePlan() {
    if (!startPoint) { toast('请先完成一次分析再保存方案'); return; }
    const u = TokenStore.getUser();
    const planName = prompt('请给本方案起名：', '我的生活圈方案');
    if (!planName) return;
    try {
        await api('/api/plan', {
            method:'POST',
            body: {
                userId: u.userId, planName,
                startType: startPoint.communityId ? 'community' : 'point',
                startLon: startPoint.lng, startLat: startPoint.lat,
                startCommunityId: startPoint.communityId,
                timeMin: currentTimeMin(),
                facilityTypes: JSON.stringify(selectedCategories()),
                weights: JSON.stringify({
                    price: document.getElementById('wPrice').value,
                    acc: document.getElementById('wAcc').value,
                    eva: document.getElementById('wEva').value
                }),
                priceMin: document.getElementById('priceMin').value,
                priceMax: document.getElementById('priceMax').value
            }
        });
        toast('方案已保存');
    } catch (e) {}
}
 
// ---------- 15. 导出 ----------
function exportAnalysis() {
    if (!startPoint) { toast('请先完成一次分析'); return; }
    const speed = Number(document.getElementById('speed').value);
    const radius = Math.round(speed * currentTimeMin());
    const token = TokenStore.getToken();
    const url = `${API_BASE}/api/export/analysis?lng=${startPoint.lng}&lat=${startPoint.lat}&radius=${radius}`;
    // 带 token 的文件下载
    fetch(url, { headers: { Authorization: 'Bearer ' + token } })
        .then(r => r.blob())
        .then(blob => {
            const a = document.createElement('a');
            a.href = URL.createObjectURL(blob);
            a.download = '可达分析结果.xlsx';
            a.click();
        });
}
 
// ---------- 通用弹窗 ----------
function setModal(html) {
    document.getElementById('modalBody').innerHTML = html;
    document.getElementById('modalMask').classList.add('show');
}
function closeModal() { document.getElementById('modalMask').classList.remove('show'); }
document.getElementById('modalMask').onclick = e => { if (e.target.id === 'modalMask') closeModal(); };
 
// ---------- 工具 ----------
function showLoading(v) { document.getElementById('loading').classList.toggle('show', v); }
function logout() {
    TokenStore.clear();
    location.href = 'login.html';
}
