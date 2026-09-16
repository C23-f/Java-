/**
 * ============================================================
 * dashboard.js —— 统计大屏 / 图表可视化
 * 对接后端 /api/stats/* 聚合接口，ECharts 渲染（深色大屏主题）
 * ============================================================
 */
window.onload = async function () {
    if (!requireLogin()) return;
    const u = TokenStore.getUser();
    document.getElementById('userName').textContent = u.username;
    document.getElementById('avatar').textContent = u.username.charAt(0).toUpperCase();
    if (TokenStore.isAdmin()) document.getElementById('adminMenu').style.display = '';
 
    await loadOverview();
    await loadCategory();
    await loadScoreDist();
    await loadPriceDist();
    await loadTop();
};
 
const AXIS = { axisLine: { lineStyle: { color: 'rgba(156,195,230,.4)' } },
               axisLabel: { color: '#9cc3e6' }, splitLine: { lineStyle: { color: 'rgba(156,195,230,.12)' } } };
 
// 1. 顶部指标卡
async function loadOverview() {
    try {
        const d = await api('/api/stats/overview');
        document.getElementById('kFac').textContent = d.facilityTotal ?? 0;
        document.getElementById('kCom').textContent = d.communityTotal ?? 0;
        document.getElementById('kPrice').textContent = Math.round(d.avgPrice ?? 0);
        document.getElementById('kScore').textContent = Number(d.avgCommunityScore ?? 0).toFixed(1);
    } catch (e) {}
}
 
// 2. 设施类别：柱状 + 环形（同一份数据）
async function loadCategory() {
    const data = await api('/api/stats/facilityByCategory');
    const names = data.map(d => d.categoryName);
    const counts = data.map(d => Number(d.count));
 
    echarts.init(document.getElementById('c1')).setOption({
        tooltip: { trigger: 'axis' },
        grid: { left: 40, right: 20, top: 20, bottom: 30 },
        xAxis: { type: 'category', data: names, ...AXIS },
        yAxis: { type: 'value', ...AXIS },
        series: [{ type: 'bar', data: counts, itemStyle: {
            color: { type: 'linear', x:0,y:0,x2:0,y2:1, colorStops:[
                {offset:0,color:'#2ec4b6'},{offset:1,color:'#1676d6'}] },
            borderRadius: [6,6,0,0] } }]
    });
 
    echarts.init(document.getElementById('c2')).setOption({
        tooltip: { trigger: 'item' },
        legend: { bottom: 0, textStyle: { color: '#9cc3e6' } },
        series: [{
            type: 'pie', radius: ['40%','68%'],
            data: data.map(d => ({ name: d.categoryName, value: Number(d.count) })),
            label: { color: '#cfe8ff' },
            itemStyle: { borderColor: '#071a30', borderWidth: 2 }
        }]
    });
}
 
// 3. 评分等级分布
async function loadScoreDist() {
    const data = await api('/api/stats/scoreDistribution');
    echarts.init(document.getElementById('c3')).setOption({
        tooltip: { trigger: 'axis' },
        grid: { left: 40, right: 20, top: 20, bottom: 30 },
        xAxis: { type: 'category', data: data.map(d => d.name), ...AXIS },
        yAxis: { type: 'value', ...AXIS },
        series: [{ type: 'bar', data: data.map(d => Number(d.count)),
            itemStyle: { color: '#f59e0b', borderRadius: [6,6,0,0] } }]
    });
}
 
// 4. 房价分布
async function loadPriceDist() {
    const data = await api('/api/stats/priceDistribution');
    echarts.init(document.getElementById('c4')).setOption({
        tooltip: { trigger: 'axis' },
        grid: { left: 50, right: 20, top: 20, bottom: 30 },
        xAxis: { type: 'category', data: data.map(d => d.name), ...AXIS },
        yAxis: { type: 'value', ...AXIS },
        series: [{ type: 'bar', data: data.map(d => Number(d.count)),
            itemStyle: { color: '#a855f7', borderRadius: [6,6,0,0] } }]
    });
}
 
// 5. Top8 设施排行
async function loadTop() {
    const data = await api('/api/stats/topFacilities', { query: { limit: 8 } });
    echarts.init(document.getElementById('c5')).setOption({
        tooltip: { trigger: 'axis' },
        grid: { left: 130, right: 40, top: 10, bottom: 20 },
        xAxis: { type: 'value', ...AXIS },
        yAxis: { type: 'category', inverse: true, data: data.map(d => d.name),
                 axisLabel: { color: '#cfe8ff' } },
        series: [{ type: 'bar', data: data.map(d => Number(d.score)),
            itemStyle: { color: '#22c55e', borderRadius: [0,6,6,0] },
            label: { show: true, position: 'right', color: '#cfe8ff' } }]
    });
}
 
// 导出统计报表（Excel，带token下载）
function exportReport() {
    const token = TokenStore.getToken();
    const rows = [
        { name: '小区数据表', url: '/api/export/communities', file: '张店区居住小区数据.xlsx' },
        { name: '设施数据表', url: '/api/export/facilities', file: '张店区便民设施数据.xlsx' }
    ];
    let done = 0;
    rows.forEach(r => {
        fetch(API_BASE + r.url, { headers: { Authorization: 'Bearer ' + token } })
            .then(resp => {
                if (!resp.ok) throw new Error('导出失败');
                return resp.blob();
            })
            .then(blob => {
                const a = document.createElement('a');
                a.href = URL.createObjectURL(blob);
                a.download = r.file;
                a.click();
                done++;
                if (done === rows.length) toast('统计报表导出完成');
            })
            .catch(e => toast(r.name + '导出失败'));
    });
}

function logout() { TokenStore.clear(); location.href = 'login.html'; }
