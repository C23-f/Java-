/**
 * ============================================================
 * config.js —— 前端全局配置与公共工具
 * 功能：后端接口基址、高德地图Key、登录令牌存取、统一ajax请求封装、
 *       登录态/权限判断、消息提示。所有页面都引用本文件。
 * ============================================================
 */
 
// ---------- 全局配置 ----------
// 后端服务地址（SpringBoot 8080端口）。前端用本地静态文件直接打开时，跨域由后端CorsConfig放行。
const API_BASE = 'http://localhost:8080';
 
// 【需要你自己填】高德地图JS API 2.0 的 Key。
// 申请地址：https://console.amap.com/dev/key/app  → 创建应用 → 添加 Key → 服务平台选「Web端(JS API)」
// 申请后还需在同一页面开启「安全密钥」，把值填到下方 SECURITY_CODE。
const AMAP_KEY = '698dfb27413eb152a809a7a13009488f';
const AMAP_SECURITY_CODE = 'd5bf0f930e7b55dadcd35863d958c5f3';
 
// 张店区地图初始中心 [经度, 纬度]（GCJ-02，与高德一致，无需转换）
const MAP_CENTER = [118.0568, 36.8139];
const MAP_ZOOM = 13;
 
// ---------- 登录令牌存取 ----------
// 登录成功后把 JWT 存在 localStorage，后续请求自动带在 Authorization 头
const TokenStore = {
    getToken()  { return localStorage.getItem('token'); },
    setToken(t) { localStorage.setItem('token', t); },
    clear()     { localStorage.removeItem('token'); localStorage.removeItem('user'); },
 
    // 当前登录用户对象（含 userId / username / roleCode）
    getUser() {
        try { return JSON.parse(localStorage.getItem('user')); }
        catch (e) { return null; }
    },
    setUser(u) { localStorage.setItem('user', JSON.stringify(u)); },
 
    isLogin() { return !!this.getToken(); },
    // 是否管理员/运营（数据管理权限）
    isAdmin() {
        const u = this.getUser();
        return u && (u.roleCode === 'admin' || u.roleCode === 'operator');
    },
    // 是否超级管理员（用户/角色/日志管理）
    // 兼容新旧两种 user 缓存：roleCode==='admin' 或 roleId===1 均为管理员
    isSuperAdmin() {
        const u = this.getUser();
        return u && (u.roleCode === 'admin' || u.roleId === 1);
    }
};
 
/**
 * 统一请求封装（fetch 封装）
 * @param {string} url    接口路径，如 /api/community/list（可省略 http://localhost:8080）
 * @param {object} options { method, body, query }
 * @returns {Promise<any>} 解析后的 data 字段；code!=200 时 reject
 */
async function api(url, options = {}) {
    const { method = 'GET', body = null, query = null } = options;
    let fullUrl = url.startsWith('http') ? url : API_BASE + url;
 
    // 拼接 query 参数
    if (query) {
        const qs = Object.entries(query)
            .filter(([k, v]) => v !== undefined && v !== null && v !== '')
            .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
            .join('&');
        if (qs) fullUrl += (fullUrl.includes('?') ? '&' : '?') + qs;
    }
 
    const headers = { 'Content-Type': 'application/json' };
    const token = TokenStore.getToken();
    if (token) headers['Authorization'] = 'Bearer ' + token;
 
    let resp;
    // 20 秒超时：后端未启动/网络异常时快速失败，避免页面一直卡在加载；
    // 正常的大列表请求（1352 条设施）在本地环境通常 1 秒内完成，不会被误杀
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 20000);
    try {
        resp = await fetch(fullUrl, {
            method,
            headers,
            body: body ? JSON.stringify(body) : null,
            signal: controller.signal
        });
    } catch (e) {
        clearTimeout(timer);
        toast('后端连接超时或异常(' + API_BASE + ')，请确认后端服务已启动');
        throw e;
    }
    clearTimeout(timer);
 
    // 401 未登录/登录过期：跳回登录页
    if (resp.status === 401) {
        TokenStore.clear();
        location.href = 'login.html';
        throw new Error('未登录');
    }
    // 403 无权限
    if (resp.status === 403) {
        toast('没有权限执行该操作');
        throw new Error('无权限');
    }
 
    const json = await resp.json();
    if (json.code !== 200) {
        toast(json.msg || '请求失败');
        throw new Error(json.msg);
    }
    return json.data;
}
 
// ---------- 轻量提示（玻璃拟态小浮层） ----------
let _toastTimer = null;
function toast(msg) {
    let el = document.getElementById('__toast');
    if (!el) {
        el = document.createElement('div');
        el.id = '__toast';
        el.style.cssText = 'position:fixed;top:24px;left:50%;transform:translateX(-50%);' +
            'background:rgba(30,40,50,.82);color:#fff;padding:10px 22px;border-radius:12px;' +
            'font-size:14px;z-index:99999;backdrop-filter:blur(8px);box-shadow:0 6px 20px rgba(0,0,0,.25);' +
            'transition:opacity .3s;opacity:0;';
        document.body.appendChild(el);
    }
    el.textContent = msg;
    el.style.opacity = '1';
    clearTimeout(_toastTimer);
    _toastTimer = setTimeout(() => { el.style.opacity = '0'; }, 2200);
}
 
// ---------- 登录守卫：未登录访问内页时跳登录 ----------
function requireLogin() {
    if (!TokenStore.isLogin()) {
        location.href = 'login.html';
        return false;
    }
    return true;
}
