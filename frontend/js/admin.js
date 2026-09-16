/**
 * ============================================================
 * admin.js —— 数据管理后台
 * 8 个标签页：小区/设施/评价审核/分类/街道/收藏/用户/操作日志
 * 全部对接后端 REST 接口，按角色控制菜单与操作按钮
 * ============================================================
 */
let state = { tab: 'community', page: 1, size: 10, total: 0 };
 
window.onload = async function () {
    if (!requireLogin()) return;
    const u = TokenStore.getUser();
    document.getElementById('userName').textContent = u.username;
    document.getElementById('avatar').textContent = u.username.charAt(0).toUpperCase();
    // 用户管理/操作日志仅管理员(admin)可见，运营/观察者隐藏
    if (!TokenStore.isSuperAdmin()) {
        document.getElementById('tabUser').style.display = 'none';
        document.getElementById('tabLog').style.display = 'none';
        // 若当前停留在被隐藏的页签，强制切回小区管理
        if (state.tab === 'user' || state.tab === 'log') { state.tab = 'community'; }
    }
    // 标签切换
    document.querySelectorAll('#tabs .tab').forEach(t => {
        t.onclick = () => {
            document.querySelectorAll('#tabs .tab').forEach(x => x.classList.remove('active'));
            t.classList.add('active');
            state.tab = t.dataset.t;
            state.page = 1;
            renderFilter();
            loadTable();
        };
    });
    renderFilter();
    loadTable();
};
 
// ---------- 各标签页配置：列定义 ----------
const TAB_CONFIG = {
    community: {
        cols: [['communityId','ID'],['communityName','小区名'],['address','地址'],['price','房价'],['avgScore','评分'],['household','户数'],['districtName','街道']],
        list: p => api('/api/community/page', { query: { ...p } }),
        hasAdd: true, addTitle: '新增小区'
    },
    facility: {
        cols: [['facilityId','ID'],['facilityName','设施名'],['categoryName','分类'],['address','地址'],['avgScore','评分'],['openTime','开放时间'],['phone','电话']],
        list: p => api('/api/facility/page', { query: { ...p } }),
        hasAdd: true, addTitle: '新增设施'
    },
    evaluation: {
        cols: [['id','ID'],['objectType','对象'],['objectId','对象ID'],['score','星级'],['content','内容'],['status','状态'],['createTime','时间']],
        list: p => api('/api/evaluation/page', { query: { ...p } })
    },
    category: {
        cols: [['categoryId','ID'],['categoryCode','编码'],['categoryName','名称'],['weight','权重'],['sortOrder','排序']],
        list: async p => ({ list: await api('/api/category/list'), total: (await api('/api/category/list')).length })
    },
    favorite: {
        cols: [['id','ID'],['userId','用户'],['objectType','类型'],['objectId','对象ID'],['remark','备注'],['createTime','收藏时间']],
        list: async p => {
            const u = TokenStore.getUser();
            const l = await api('/api/favorite/list', { query: { userId: u.userId } });
            return { list: l, total: l.length };
        }
    },
    user: {
        cols: [['userId','ID'],['username','用户名'],['realName','姓名'],['phone','手机'],['roleName','角色'],['status','状态']],
        list: async p => { const l = await api('/api/user/list'); return { list: l, total: l.length }; }
    },
    log: {
        cols: [['id','ID'],['operatorName','操作人'],['action','操作'],['module','模块'],['detail','详情'],['createTime','时间']],
        list: p => api('/api/log/list', { query: { ...p } })
    }
};
 
// ---------- 筛选条 ----------
function renderFilter() {
    const bar = document.getElementById('filterBar');
    const t = state.tab;
    let html = '';
    if (t === 'community') html = `<input id="fKw" placeholder="小区名称关键字" onkeydown="if(event.key==='Enter')reload()"><button class="btn btn-sm" onclick="reload()">查询</button>`;
    if (t === 'facility')  html = `<input id="fKw" placeholder="设施名称关键字" onkeydown="if(event.key==='Enter')reload()"><button class="btn btn-sm" onclick="reload()">查询</button>`;
    if (t === 'evaluation') html = `
        <select id="fStatus">
            <option value="">全部状态</option><option value="0">待审核</option>
            <option value="1">已通过</option><option value="2">已驳回</option>
        </select><button class="btn btn-sm" onclick="reload()">查询</button>`;
    bar.innerHTML = html;
 
    // 工具按钮
    document.getElementById('toolLeft').innerHTML = (t === 'community' || t === 'facility')
        ? `<button class="btn btn-sm" onclick="openEdit()">+ 新增</button>` : '';
    document.getElementById('toolRight').innerHTML =
        `<button class="btn btn-ghost btn-sm" onclick="exportXlsx()">导出Excel</button>`;
}
 
function reload() { state.page = 1; loadTable(); }
 
// ---------- 加载并渲染表格 ----------
async function loadTable() {
    showLoading(true);
    const cfg = TAB_CONFIG[state.tab];
    let query = { page: state.page, size: state.size };
    if (state.tab === 'community' || state.tab === 'facility') {
        const kw = document.getElementById('fKw');
        if (kw && kw.value) query.keyword = kw.value;
    }
    if (state.tab === 'evaluation') {
        const st = document.getElementById('fStatus');
        if (st && st.value) query.status = st.value;
    }
 
    try {
        const res = await cfg.list(query);
        // 统一两种返回：{list,total} 或 直接数组
        const rows = res.list || res;
        state.total = res.total || rows.length;
        renderTable(cfg.cols, rows);
        document.getElementById('pageInfo').textContent = `第 ${state.page} 页 / 共 ${Math.max(1,Math.ceil(state.total/state.size))} 页`;
    } catch (e) {}
    showLoading(false);
}
 
function renderTable(cols, rows) {
    document.getElementById('thead').innerHTML =
        '<tr>' + cols.map(c => `<th>${c[1]}</th>`).join('') + '<th>操作</th></tr>';
 
    document.getElementById('tbody').innerHTML = rows.length ? rows.map(r => {
        let tds = cols.map(c => {
            let v = r[c[0]];
            if (c[0] === 'status' && state.tab === 'evaluation')
                v = v === 0 ? '<span class="badge badge-wait">待审核</span>'
                  : v === 1 ? '<span class="badge badge-ok">已通过</span>'
                  : '<span class="badge badge-no">已驳回</span>';
            if (c[0] === 'objectType') v = v === 'community' ? '小区' : '设施';
            if (v === null || v === undefined) v = '--';
            return `<td>${v}</td>`;
        }).join('');
        // 操作列
        let ops = '';
        if (state.tab === 'community' || state.tab === 'facility') {
            ops = `<button class="btn btn-ghost btn-sm" onclick='openEdit(${JSON.stringify(r)})'>编辑</button>
                   <button class="btn btn-danger btn-sm" onclick="delRow(${r[cols[0][0]]})">删除</button>`;
        } else if (state.tab === 'evaluation' && r.status === 0) {
            ops = `<button class="btn btn-sm" onclick="auditRow(${r.id},1)">通过</button>
                   <button class="btn btn-danger btn-sm" onclick="auditRow(${r.id},2)">驳回</button>`;
        }
        return `<tr>${tds}<td>${ops}</td></tr>`;
    }).join('') : '<tr><td colspan="9" class="empty">暂无数据</td></tr>';
}
 
// ---------- 新增/编辑（小区、设施） ----------
function openEdit(row) {
    const isCom = state.tab === 'community';
    const f = row || {};
    setModal(`
        <h3>${row ? '编辑' : '新增'}${isCom?'小区':'设施'}</h3>
        ${isCom ? `
        <div class="field"><label>小区名称</label><input id="f1" value="${f.communityName||''}"></div>
        <div class="field"><label>地址</label><input id="f2" value="${f.address||''}"></div>
        <div class="field"><label>房价(元/㎡)</label><input id="f3" type="number" value="${f.price||''}"></div>
        <div class="field"><label>经度</label><input id="f4" value="${f.longitude||''}"></div>
        <div class="field"><label>纬度</label><input id="f5" value="${f.latitude||''}"></div>` : `
        <div class="field"><label>设施名称</label><input id="f1" value="${f.facilityName||''}"></div>
        <div class="field"><label>分类ID</label><input id="f2" type="number" value="${f.categoryId||''}"></div>
        <div class="field"><label>地址</label><input id="f3" value="${f.address||''}"></div>
        <div class="field"><label>经度</label><input id="f4" value="${f.longitude||''}"></div>
        <div class="field"><label>纬度</label><input id="f5" value="${f.latitude||''}"></div>`}
        <button class="btn" style="width:100%" onclick="saveEdit(${row ? row[isCom?'communityId':'facilityId'] : 'null'})">保存</button>
    `);
}
 
async function saveEdit(id) {
    const isCom = state.tab === 'community';
    const body = isCom
        ? { communityId: id||undefined, communityName: v('f1'), address: v('f2'), price: Number(v('f3'))||null, longitude: Number(v('f4')), latitude: Number(v('f5')) }
        : { facilityId: id||undefined, facilityName: v('f1'), categoryId: Number(v('f2')), address: v('f3'), longitude: Number(v('f4')), latitude: Number(v('f5')) };
    try {
        await api(isCom ? '/api/community' : '/api/facility', {
            method: id ? 'PUT' : 'POST', body
        });
        toast('保存成功'); closeModal(); loadTable();
    } catch (e) {}
}
function v(id) { return document.getElementById(id).value.trim(); }
 
// 删除
async function delRow(id) {
    if (!confirm('确认删除该记录？')) return;
    try {
        await api((state.tab === 'community' ? '/api/community/' : '/api/facility/') + id, { method: 'DELETE' });
        toast('删除成功'); loadTable();
    } catch (e) {}
}
 
// 评价审核
async function auditRow(id, status) {
    const rejectReason = status === 2 ? (prompt('驳回理由：') || '') : null;
    try {
        await api('/api/evaluation/audit', {
            method:'POST', body: { id, status, rejectReason }
        });
        toast('已审核'); loadTable();
    } catch (e) {}
}
 
// ---------- 导出 ----------
function exportXlsx() {
    const map = { community:'/api/export/communities', facility:'/api/export/facilities',
                  evaluation:'/api/export/evaluations' };
    const url = map[state.tab];
    if (!url) { toast('当前页暂不支持导出'); return; }
    const token = TokenStore.getToken();
    fetch(API_BASE + url, { headers: { Authorization: 'Bearer ' + token } })
        .then(r => r.blob()).then(b => {
            const a = document.createElement('a');
            a.href = URL.createObjectURL(b); a.download = state.tab + '.xlsx'; a.click();
        });
}
 
// ---------- 分页 ----------
function changePage(d) {
    const max = Math.max(1, Math.ceil(state.total / state.size));
    state.page = Math.min(max, Math.max(1, state.page + d));
    loadTable();
}
 
// ---------- 弹窗/工具 ----------
function setModal(html) { document.getElementById('modalBody').innerHTML = html; document.getElementById('modalMask').classList.add('show'); }
function closeModal() { document.getElementById('modalMask').classList.remove('show'); }
function showLoading(v) { document.getElementById('loading').classList.toggle('show', v); }
function logout() { TokenStore.clear(); location.href = 'login.html'; }
