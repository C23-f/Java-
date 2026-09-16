/**
 * ============================================================
 * main.js —— 系统主界面逻辑
 * 对接后端：小区/设施/分类查询、缓冲区分析、评价、收藏、方案、搜索、AI
 * 依赖：config.js（api/toast/TokenStore）、高德地图JS API 2.0
 *
 * 功能清单（对照需求说明书）：
 *  1. 地图初始化 + 底图切换（标准/卫星）
 *  2. 设施点：散点 / 按分类聚合标注 两种模式（默认聚合）
 *  3. 小区点位：房形图钉，按房价变色
 *  4. 可达性分析：缓冲区 + 分类过滤 + 权重综合评分 + AI 综合评估
 *  5. 设施清单点击定位（平滑平移 + 高亮脉冲圈）
 *  6. 详情弹窗 + 一键导航（步行/驾车）
 *  7. 全局搜索 / 收藏 / 方案保存
 *  8. 我的收藏 / 保存方案 / 加载方案 / 评价提交 / 导出 Excel
 *  9. 每次分析自动生成图表可视化（ECharts），可导出图片
 * ============================================================
 */

// ---------- 全局状态 ----------
let map;                 // 高德地图实例
let communityMarkers = []; // 小区 marker
let facilityMarkers = [];  // 设施 marker（全部）
let facilityMarkersByCat = {}; // 按分类分组的设施 marker
let aggMarkers = [];     // 自研网格聚合圈 marker
let overlayGroup = [];    // 缓冲区/框选/高亮等叠加物
let startPoint = null;    // 当前分析起点 {lng,lat,communityId}
let categories = [];     // 设施分类
let clusterMode = true;   // 聚合标注开关（默认开启，缩小聚合、放大拆散）
let satLayer = null;
let navTool = null;       // 当前导航实例（用于清除路线）
let analysisChart = null; // 本次分析图表实例
let locHighlight = null;  // 清单定位高亮脉冲圈

// 设施分类 → 颜色与图标
// 公认分类配色：医疗红 / 教育蓝 / 商超橙 / 文体绿 / 生活紫 / 养老粉 / 交通青
// mark = 地图图标上的白色符号（纯色底 + 白字，清晰可辨）
const CAT_STYLE = {
    EDU:  { color:'#2563eb', mark:'教', icon:'📖', name:'教育' },
    MED:  { color:'#dc2626', mark:'医', icon:'✚', name:'医疗' },
    MKT:  { color:'#f97316', mark:'购', icon:'🛒', name:'商超' },
    CUL:  { color:'#16a34a', mark:'文', icon:'🌳', name:'公园' },
    LIFE: { color:'#7c3aed', mark:'活', icon:'🔧', name:'生活' },
    AGE:  { color:'#db2777', mark:'养', icon:'👵', name:'养老' },
    TRA:  { color:'#0891b2', mark:'交', icon:'🚌', name:'交通' }
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

    // 高德 JS API 2.0 必须在运行时动态加载插件（URL 上的 plugin= 参数无效）
    AMap.plugin(['AMap.MouseTool','AMap.ToolBar','AMap.Scale','AMap.Walking','AMap.Driving'], async function () {
        try {
            initMap();
            bindPanelEvents();
            // 各数据源独立加载：单个失败不影响其他（Promise.allSettled 不抛错）
            await Promise.allSettled([loadCategories(), loadCommunities(), loadFacilities()]);
        } catch (e) {
            showLoading(false);
            console.error('初始化异常:', e);
        }
        showLoading(false);
    });
};

// ---------- 1. 地图初始化 ----------
function initMap() {
    map = new AMap.Map('map', {
        zoom: MAP_ZOOM,
        center: MAP_CENTER,
        mapStyle: 'amap://styles/whitesmoke',
        viewMode: '2D'
    });
    map.addControl(new AMap.ToolBar({ position: { top: '110px', right: '10px' } }));
    map.addControl(new AMap.Scale());

    // 任意点模式：点击地图选起点
    map.on('click', e => {
        if (startMode === 'point') {
            setStartPoint(e.lnglat.getLng(), e.lnglat.getLat(), null);
        }
    });

    // 缩放/平移后重新聚合（随比例尺联动）
    map.on('zoomend', () => { if (map) renderMarkers(); });
    map.on('moveend', () => { if (map) renderMarkers(); });
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
        if (!categories || !categories.length) throw new Error('empty');
    } catch (e) {
        // 接口异常时兜底使用内置 7 类，保证分类勾选与聚合不失效
        categories = Object.keys(CAT_STYLE).map(code => ({
            categoryCode: code, categoryName: CAT_STYLE[code].name
        }));
    }
    const box = document.getElementById('catBox');
    if (!box) return;
    box.innerHTML = categories.map(c =>
        `<label class="ck-item"><input type="checkbox" value="${c.categoryCode}" checked onchange="applyFacilityFilter()">
         <span style="color:${catStyle(c.categoryCode).color}">${catStyle(c.categoryCode).icon}</span>
         ${c.categoryName}</label>`).join('');
}

// 当前勾选的分类（用于地图显隐 + 分析过滤）
function selectedCategories() {
    return [...document.querySelectorAll('#catBox input:checked')].map(i => i.value);
}

// 按分类显隐设施点：地图上只显示勾选的分类（聚合/散点统一过滤）
// 注意：未勾选任何分类时视为全部显示（避免地图空白）
function applyFacilityFilter() {
    renderMarkers();
}

// ---------- 3. 加载小区 ----------
async function loadCommunities() {
    showLoading(true);
    try {
        const list = await api('/api/community/list');
        communityMarkers = list.map(c => {
            const price = c.price ? Number(c.price) : 0;
            // 小区图标统一颜色（主题青色渐变，不再按价格分色）
            const color = '#0e6f9f';
            const m = new AMap.Marker({
                position: [Number(c.longitude), Number(c.latitude)],
                content: `<div style="
                    width:32px;height:32px;border-radius:50% 50% 50% 0;transform:rotate(-45deg);
                    background:#1676d6;border:2px solid #fff;
                    box-shadow:0 3px 9px rgba(0,0,0,.35);
                    display:flex;align-items:center;justify-content:center;">
                    <span style="transform:rotate(45deg);font-size:14px;">🏠</span></div>`,
                offset: new AMap.Pixel(-16, -16)
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
    } catch (e) {
        console.error('小区加载失败:', e);
        toast('小区数据加载失败，请确认后端服务已启动');
    } finally {
        showLoading(false); // 无论成功失败都关闭 loading，避免页面卡死
    }
}

// ---------- 4. 加载设施 ----------
async function loadFacilities() {
    let list = [];
    try {
        list = await api('/api/facility/list');
    } catch (e) {
        console.error('设施加载失败:', e);
        toast('设施数据加载失败，请确认后端服务已启动');
        // 失败时也保留小区点显示，不静默空白
        renderMarkers();
        return;
    }
    facilityMarkers = list.map(f => {
        const st = catStyle(f.categoryCode);
        const m = new AMap.Marker({
            position: [Number(f.longitude), Number(f.latitude)],
            content: `<div style="
                width:30px;height:30px;border-radius:50% 50% 50% 0;transform:rotate(-45deg);
                background:${st.color};border:2px solid #fff;
                box-shadow:0 3px 8px rgba(0,0,0,.32);
                display:flex;align-items:center;justify-content:center;">
                <span style="transform:rotate(45deg);font-size:13px;">${st.icon}</span></div>`,
            offset: new AMap.Pixel(-15, -15)
        });
        m.on('click', () => openFacilityDetail(f));
        m._data = f;
        return m;
    });
    // 按分类分组（供按分类聚合）
    facilityMarkersByCat = {};
    facilityMarkers.forEach(m => {
        const code = m._data.categoryCode || 'OTHER';
        (facilityMarkersByCat[code] = facilityMarkersByCat[code] || []).push(m);
    });
    renderMarkers();
}

// 当前应显示的设施 marker（按勾选分类过滤；未勾选=全部显示）
function visibleFacilityMarkers() {
    const cats = selectedCategories();
    if (!cats.length) return facilityMarkers;
    return facilityMarkers.filter(m => cats.includes(m._data.categoryCode));
}

// 当前应显示的设施分组（按分类，供聚合；未勾选=全部分组）
function visibleFacilityGroups() {
    const cats = selectedCategories();
    const groups = {};
    if (cats.length) {
        cats.forEach(c => { if (facilityMarkersByCat[c]) groups[c] = facilityMarkersByCat[c]; });
    } else {
        Object.keys(facilityMarkersByCat).forEach(c => { groups[c] = facilityMarkersByCat[c]; });
    }
    return groups;
}

// 自研网格聚合渲染：
//   按当前缩放级别将设施点按屏幕网格聚合——缩小视图(zoom小)聚合圈大而少，
//   放大视图(zoom大)网格变小、逐个拆散显示，随比例尺自动联动。
//   不依赖官方 MarkerCluster 插件，保证聚合标注必定生效。
function renderFacilityLayer() {
    // 清旧：设施散点 + 聚合圈
    facilityMarkers.forEach(m => m.setMap(null));
    aggMarkers.forEach(g => { try { g.setMap(null); } catch(e){} });
    aggMarkers = [];

    const markers = visibleFacilityMarkers();
    if (!markers.length || !map) return;

    const zoom = map.getZoom();
    // 网格像素大小随缩放变化：zoom 越小网格越大(聚合粗)，zoom 越大网格越小(拆散细)
    const gridPx = Math.max(55, 310 - zoom * 16); // 聚合更粗：z10:150 z13:102 z15:70 z17:38→55

    // 按容器像素坐标分桶（视野外粗略剔除）
    const buckets = {};
    markers.forEach(m => {
        let px;
        try { px = map.lngLatToContainer(m.getPosition()); } catch(e) { return; }
        if (px.x < -gridPx || px.y < -gridPx || px.x > 3000 + gridPx || px.y > 2000 + gridPx) return;
        const gx = Math.floor(px.x / gridPx);
        const gy = Math.floor(px.y / gridPx);
        const key = gx + '_' + gy;
        (buckets[key] = buckets[key] || []).push(m);
    });

    Object.keys(buckets).forEach(key => {
        const ms = buckets[key];
        // 单点：直接显示原散点
        if (ms.length === 1) { ms[0].setMap(map); return; }
        // 多点：合并为一个聚合圈（显示数量 + 分类图标）
        const lng = ms.reduce((s, m) => s + m.getPosition().getLng(), 0) / ms.length;
        const lat = ms.reduce((s, m) => s + m.getPosition().getLat(), 0) / ms.length;
        const st = catStyle(ms[0]._data.categoryCode);
        // 聚合圈：统一大小、不显示数字、不触发放大
        const size = 36;
        const agg = new AMap.Marker({
            position: [lng, lat],
            content: `<div style="width:${size}px;height:${size}px;border-radius:50%;
                background:${st.color};color:#fff;
                font-size:16px;border:2px solid #fff;
                box-shadow:0 2px 8px rgba(0,0,0,.32);
                display:flex;align-items:center;justify-content:center;">
                ${st.icon}</div>`,
            offset: new AMap.Pixel(-size/2, -size/2),
            zIndex: 200
        });
        agg.setMap(map);
        aggMarkers.push(agg);
    });
}

// 渲染所有点位：小区散点 + 设施聚合（打开页面即默认聚合显示全部）
function renderMarkers() {
    // 先清旧
    communityMarkers.forEach(m => m.setMap(null));
    facilityMarkers.forEach(m => m.setMap(null));
    aggMarkers.forEach(g => { try { g.setMap(null); } catch(e){} });
    aggMarkers = [];
    if (locHighlight) { locHighlight.setMap(null); locHighlight = null; }

    // 小区始终散点显示
    communityMarkers.forEach(m => m.setMap(map));

    // 设施：自研网格聚合（随缩放自动合并/拆散）
    renderFacilityLayer();
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

        // 生成本次分析图表（设施分类分布）
        renderAnalysisChart(filtered, communities);

        // AI 综合评估（后端 /api/ai/analysis：AI 评分 + 平均房价 + 建议）
        try {
            const ai = await api('/api/ai/analysis', {
                method: 'POST',
                body: { lng: startPoint.lng, lat: startPoint.lat, radius, categories: cats }
            });
            renderAiAdvice(ai);
        } catch (e) {}
    } catch (e) {
    }
    showLoading(false);
}

// ---------- 7.5 本次分析图表（ECharts，每次分析重新生成，可导出） ----------
function renderAnalysisChart(facs, coms) {
    const el = document.getElementById('analysisChart');
    if (!el) return;
    if (typeof echarts === 'undefined') {
        el.innerHTML = '<div class="empty">图表库未加载</div>';
        return;
    }
    // 设施分类分布（柱状图）
    const catCount = {};
    facs.forEach(f => {
        const code = f.categoryCode || 'OTHER';
        catCount[code] = (catCount[code] || 0) + 1;
    });
    const codes = Object.keys(catCount);
    if (!codes.length) {
        el.innerHTML = '<div class="empty">本次分析无设施数据</div>';
        return;
    }
    if (!analysisChart) analysisChart = echarts.init(el);
    analysisChart.setOption({
        tooltip: { trigger: 'axis' },
        grid: { left: 44, right: 18, top: 26, bottom: 26 },
        xAxis: { type: 'category',
            data: codes.map(c => catStyle(c).name),
            axisLabel: { color: '#46566a', fontSize: 11 },
            axisLine: { lineStyle: { color: 'rgba(120,160,190,.4)' } } },
        yAxis: { type: 'value', minInterval: 1,
            axisLabel: { color: '#46566a', fontSize: 11 },
            splitLine: { lineStyle: { color: 'rgba(120,160,190,.18)' } } },
        series: [{
            name: '设施数量', type: 'bar', barWidth: '52%',
            data: codes.map(c => ({ value: catCount[c],
                itemStyle: { color: catStyle(c).color, borderRadius: [6,6,0,0] } })),
            label: { show: true, position: 'top', fontSize: 11, color: '#33475b' }
        }]
    }, true);
}

// 导出本次分析图表为图片
function exportChart() {
    if (!analysisChart) { toast('请先完成一次可达性分析'); return; }
    try {
        const url = analysisChart.getDataURL({ type: 'png', pixelRatio: 2, backgroundColor: '#fff' });
        const a = document.createElement('a');
        a.href = url;
        a.download = '本次分析设施分布图表.png';
        a.click();
        toast('图表已导出');
    } catch (e) { toast('图表导出失败'); }
}

// 渲染右侧 AI 综合评估卡片
function renderAiAdvice(ai) {
    document.getElementById('aiAdvice').textContent = ai.advice || '暂无 AI 建议';
    const meta = document.getElementById('aiMeta');
    meta.style.display = 'flex';
    const stats = ai.categoryStats || {};
    const catHtml = Object.keys(stats).slice(0, 7).map(k =>
        `<span><b>${catStyle(k).icon}${catStyle(k).name}</b> ${stats[k]}个</span>`).join('');
    meta.innerHTML =
        `<span>AI评分 <b>${ai.score100 || '--'}</b> 分</span>
         <span>平均房价 <b>${ai.avgPrice ? ai.avgPrice.toLocaleString() : '--'}</b> 元/㎡</span>
         <span>设施 <b>${ai.facilityCount || 0}</b> 个 · 小区 <b>${ai.communityCount || 0}</b> 个</span>
         ${catHtml}`;
}

// 渲染右侧结果
function renderResult(facs, coms) {
    document.getElementById('kpiFac').textContent = facs.length;
    document.getElementById('kpiCom').textContent = coms.length;
    // 平均房价
    const prices = coms.map(c => Number(c.price)).filter(v => v > 0);
    const avgP = prices.length ? Math.round(prices.reduce((a,b)=>a+b,0)/prices.length) : 0;
    document.getElementById('kpiAvg').textContent = avgP ? avgP.toLocaleString() : '--';
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
            <div class="sub">${c.price?Number(c.price).toLocaleString()+' 元/㎡ · ':''}评分 ${c.avgScore||'--'}</div>
        </li>`).join('') : '<li class="empty">该范围内无小区</li>';
}

// 清单点击定位：平滑平移 + 高亮脉冲圈（不缩放）
function locate(lng, lat) {
    if (locHighlight) { locHighlight.setMap(null); locHighlight = null; }
    locHighlight = new AMap.Marker({
        position: [lng, lat],
        content: `<div class="loc-pulse"></div>`,
        offset: new AMap.Pixel(-13, -13),
        zIndex: 200
    });
    locHighlight.setMap(map);
    // 平滑平移到目标位置（保持当前缩放级别）
    map.panTo([lng, lat]);
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
        <div class="detail-row"><span>房价</span><b>${c.price?Number(c.price).toLocaleString()+' 元/㎡':'--'}</b></div>
        <div class="detail-row"><span>户数 / 人口</span><b>${c.houseCount||'-'} / ${c.population||'-'}</b></div>
        <div class="detail-row"><span>用户平均评分</span><b>${c.avgScore?Number(c.avgScore).toFixed(1):'--'}</b></div>
        <div class="detail-row"><span>所属街道</span><b>${c.districtName||'--'}</b></div>
        <div style="margin-top:12px;font-size:13px;font-weight:600">用户评价</div>
        <div id="evalBox">${evalsHtml}</div>
        <div class="field" style="margin-top:10px">
            <select id="myScore"><option value="5">★★★★★ 非常满意</option><option value="4">★★★★ 满意</option><option value="3">★★★ 一般</option><option value="2">★★ 较差</option><option value="1">★ 很差</option></select>
            <textarea id="myEval" rows="2" placeholder="写下你的评价（提交后待管理员审核）"></textarea>
        </div>
        <div style="display:flex;gap:8px;flex-wrap:wrap">
            <button class="btn" onclick="submitEval('community',${c.communityId})">提交评价</button>
            <button class="btn btn-ghost" onclick="fav('community',${c.communityId})">☆ 收藏</button>
            <button class="btn btn-ghost" onclick="closeModal();setStartPoint(${Number(c.longitude)},${Number(c.latitude)},${c.communityId})">以此为起点分析</button>
            <button class="btn btn-ghost" onclick="navigateTo(${Number(c.longitude)},${Number(c.latitude)},'${c.communityName}')">🧭 一键导航</button>
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
        <div style="display:flex;gap:8px;flex-wrap:wrap">
            <button class="btn" onclick="submitEval('facility',${f.facilityId})">提交评价</button>
            <button class="btn btn-ghost" onclick="fav('facility',${f.facilityId})">☆ 收藏</button>
            <button class="btn btn-ghost" onclick="navigateTo(${Number(f.longitude)},${Number(f.latitude)},'${f.facilityName}')">🧭 一键导航</button>
        </div>
    `);
}

// ---------- 9.5 一键导航（步行优先，驾车兜底；路线可被清除） ----------
function navigateTo(lng, lat, name) {
    if (!startPoint) { toast('请先在地图选择分析起点（点选起点后即可导航）'); return; }
    const end = new AMap.LngLat(lng, lat);
    const start = new AMap.LngLat(startPoint.lng, startPoint.lat);
    // 步行规划（15分钟生活圈场景默认步行）
    if (typeof AMap.Walking !== 'undefined') {
        const walking = new AMap.Walking({ map, panel: '' });
        navTool = walking; // 记录实例，便于清除路线
        walking.search(start, end, (status, result) => {
            if (status === 'complete' && result.routes && result.routes.length) {
                showNavResult(name, '步行', result.routes[0]);
            } else {
                drivingNav(start, end, name); // 步行失败自动转驾车
            }
        });
    } else {
        drivingNav(start, end, name);
    }
}

function drivingNav(start, end, name) {
    if (typeof AMap.Driving === 'undefined') { toast('导航组件加载失败'); return; }
    const driving = new AMap.Driving({ map, panel: '' });
    navTool = driving; // 记录实例，便于清除路线
    driving.search(start, end, (status, result) => {
        if (status === 'complete' && result.routes && result.routes.length) {
            showNavResult(name, '驾车', result.routes[0]);
        } else {
            toast('未能规划出路线，请检查起点与终点');
        }
    });
}

function showNavResult(name, mode, route) {
    const distance = route.distance ? (route.distance / 1000).toFixed(2) + ' km' : '--';
    const time = route.time ? Math.ceil(route.time / 60) + ' 分钟' : '--';
    setModal(`
        <h3>🧭 导航到「${name}」</h3>
        <div class="detail-row"><span>出行方式</span><b>${mode}</b></div>
        <div class="detail-row"><span>预计距离</span><b>${distance}</b></div>
        <div class="detail-row"><span>预计耗时</span><b>${time}</b></div>
        <div class="eval-item" style="margin-top:12px">
            高德地图已在地图上绘制路线（蓝色折线）。如需语音逐段导航，请在高德地图 App 中搜索目的地。
        </div>
        <div style="display:flex;gap:8px;margin-top:12px">
            <button class="btn" onclick="closeModal();locate(${startPoint.lng},${startPoint.lat})">回到起点</button>
            <button class="btn btn-ghost" onclick="closeModal()">关闭</button>
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
            locate(Number(c.longitude), Number(c.latitude));
            openCommunityDetail(c);
        } else if (data.facilities.length) {
            const f = data.facilities[0];
            locate(Number(f.longitude), Number(f.latitude));
            openFacilityDetail(f);
        } else {
            toast('未找到匹配结果');
        }
    } catch (e) {}
}

// ---------- 11. 工具 ----------
// ---------- 11. 工具 ----------

function clearOverlays() {
    overlayGroup.forEach(o => { try { o.setMap(null); } catch(e){} });
    overlayGroup = [];
    if (locHighlight) { locHighlight.setMap(null); locHighlight = null; }
    // 清除导航路线（导航实例 clear 移除地图上的路线折线）
    if (navTool) {
        try { navTool.clear(); } catch(e) {}
        navTool = null;
    }
}
function clearAll() {
    clearOverlays();
    startPoint = null;
    document.getElementById('facList').innerHTML = '<li class="empty">尚未分析</li>';
    document.getElementById('comList').innerHTML = '<li class="empty">尚未分析</li>';
    document.getElementById('aiAdvice').textContent = '完成一次可达性分析后，将在这里生成 AI 生活圈评估与建议。';
    document.getElementById('aiMeta').style.display = 'none';
    // 清空本次分析图表
    if (analysisChart) { analysisChart.clear(); }
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

// ---------- 14.5 我的方案（加载已保存方案） ----------
async function openPlans() {
    const u = TokenStore.getUser();
    let list = [];
    try {
        list = await api('/api/plan/list/' + u.userId);
    } catch (e) {}
    if (!list.length) {
        setModal(`
            <h3>📋 我的方案</h3>
            <div class="empty">还没有保存的方案。<br>在地图完成一次可达性分析后，点击顶部「保存方案」即可保存。</div>
        `);
        return;
    }
    setModal(`
        <h3>📋 我的方案（${list.length}）</h3>
        <div style="font-size:12px;color:#8aa;margin-bottom:10px">点击「应用」一键回填参数并重新执行分析</div>
        ${list.map(p => `
            <div class="eval-item" style="display:flex;justify-content:space-between;align-items:center;gap:10px">
                <div>
                    <b>${p.planName}</b>
                    <div class="sub">起点 ${p.startType==='community'?'小区':'坐标'} · ${p.timeMin}分钟 · ${p.createTime||''}</div>
                </div>
                <button class="btn btn-sm" onclick="applyPlan(${p.id})">应用</button>
            </div>`).join('')}
    `);
}

// 应用方案：回填参数并执行分析
async function applyPlan(planId) {
    try {
        const p = await api('/api/plan/' + planId);
        // 回填起点
        const lng = Number(p.startLon), lat = Number(p.startLat);
        startPoint = { lng, lat, communityId: p.startCommunityId };
        // 回填时间
        document.querySelectorAll('#timeOpts .chip').forEach(c => {
            c.className = Number(c.dataset.t) === Number(p.timeMin) ? 'chip on' : 'chip';
        });
        // 回填分类勾选
        let types = [];
        try { types = JSON.parse(p.facilityTypes || '[]'); } catch(e) {}
        document.querySelectorAll('#catBox input').forEach(i => {
            i.checked = !types.length || types.includes(i.value);
        });
        // 回填房价区间
        if (p.priceMin != null) { document.getElementById('priceMin').value = p.priceMin; document.getElementById('priceMinV').textContent = p.priceMin; }
        if (p.priceMax != null) { document.getElementById('priceMax').value = p.priceMax; document.getElementById('priceMaxV').textContent = p.priceMax; }
        // 回填权重
        try {
            const w = JSON.parse(p.weights || '{}');
            if (w.price != null) { document.getElementById('wPrice').value = w.price; document.getElementById('wPriceV').textContent = w.price; }
            if (w.acc != null) { document.getElementById('wAcc').value = w.acc; document.getElementById('wAccV').textContent = w.acc; }
            if (w.eva != null) { document.getElementById('wEva').value = w.eva; document.getElementById('wEvaV').textContent = w.eva; }
        } catch(e) {}
        closeModal();
        toast('已应用方案「' + p.planName + '」，正在重新分析…');
        setTimeout(() => runAnalysis(), 300);
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
