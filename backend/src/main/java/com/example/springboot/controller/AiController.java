package com.example.springboot.controller;

import com.example.springboot.common.BizException;
import com.example.springboot.common.Result;
import com.example.springboot.entity.Community;
import com.example.springboot.entity.Facility;
import com.example.springboot.mapper.FacilityMapper;
import com.example.springboot.service.CommunitySpatialService;
import com.example.springboot.service.FacilitySpatialService;
import jakarta.annotation.Resource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.*;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * AI 智能建议 Controller
 *
 * 1. POST /api/ai/chat —— AI 中转接口：前端把提问发给后端，后端转发到大模型，
 *    保护 API Key 不暴露在前端。ai.url 未配置时返回友好提示（可先演示规则建议）。
 * 2. GET /api/ai/advice —— 规则版智能生活建议（不依赖外部服务，答辩可直接演示）
 * 3. GET /api/ai/facilityScore/{id} —— 设施综合评分（已审核评价平均分→百分制 + 等级 + 建议）
 *
 * 所有接口需登录访问（JwtInterceptor 默认校验）
 */
@RestController
@RequestMapping("/api/ai")
public class AiController {

    private static final HttpClient HTTP = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .build();

    /** 大模型API地址，来自 application.yml 的 ai.url（空表示未启用中转） */
    @Value("${ai.url:}")
    private String aiUrl;
    /** 大模型API Key（配置在服务端，切勿下发到前端） */
    @Value("${ai.api-key:}")
    private String apiKey;
    /** 模型名称 */
    @Value("${ai.model:}")
    private String aiModel;

    @Resource
    private FacilityMapper facilityMapper;

    @Resource
    private CommunitySpatialService communitySpatialService;

    @Resource
    private FacilitySpatialService facilitySpatialService;

    /** AI 中转：POST /api/ai/chat  body: {"prompt": "..."} */
    @PostMapping("/chat")
    public Result<?> chat(@RequestBody Map<String, String> body) {
        String prompt = body.get("prompt");
        if (prompt == null || prompt.trim().isEmpty()) {
            throw new BizException("prompt 不能为空");
        }
        if (aiUrl == null || aiUrl.trim().isEmpty()) {
            return Result.error("AI 服务未配置（后端 application.yml 的 ai.url 为空），请配置大模型接口后重试；当前可使用规则版智能建议接口 /api/ai/advice");
        }
        String reqBody = "{\"model\":\"" + (aiModel == null ? "" : aiModel)
                + "\",\"messages\":[{\"role\":\"user\",\"content\":\"" + escapeJson(prompt) + "\"}]}";
        HttpRequest request = HttpRequest.newBuilder(URI.create(aiUrl.trim()))
                .timeout(Duration.ofSeconds(30))
                .header("Content-Type", "application/json;charset=UTF-8")
                .header("Authorization", "Bearer " + (apiKey == null ? "" : apiKey))
                .POST(HttpRequest.BodyPublishers.ofString(reqBody, StandardCharsets.UTF_8))
                .build();
        try {
            HttpResponse<String> resp = HTTP.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            return Result.success(resp.body());
        } catch (Exception e) {
            return Result.error("调用AI服务失败：" + e.getMessage());
        }
    }

    /** 规则版智能生活建议：GET /api/ai/advice?categoryCode=MED 或 ?categoryName=医疗 */
    @GetMapping("/advice")
    public Result<Map<String, Object>> advice(@RequestParam String categoryCode) {
        if (categoryCode == null || categoryCode.trim().isEmpty()) {
            throw new BizException("categoryCode 不能为空");
        }
        String code = categoryCode.trim().toUpperCase();
        String advice = switch (code) {
            case "EDU" -> "该区域教育资源配套良好。建议关注学校办学质量与学位供给，上下学高峰时段注意接送通勤效率。";
            case "MED" -> "该区域医疗服务覆盖较好。就医建议优先选择综合医院，日常小病可就近选择社区卫生服务站，关注开放时间与夜间急诊。";
            case "MKT" -> "该区域商业配套成熟。购物可优先选择大型商超一站式采买，日常生鲜就近购买，留意促销活动与营业时间。";
            case "CUL" -> "该区域文体活动场所充足。建议利用公园、健身场地开展日常锻炼，关注场馆开放时段与活动排期。";
            case "LIFE" -> "该区域生活服务便利。快递、家政、维修等生活服务覆盖完善，可按需选择就近服务网点。";
            case "AGE" -> "该区域养老助残设施覆盖不足或待完善。建议加强适老化改造宣传，关注社区养老服务站点建设进度。";
            case "TRA" -> "该区域公共交通便利。日常通勤可优先选择公交出行，关注首末班时间与换乘接驳。";
            default -> "暂未收录该类设施的专属建议，建议结合周边实际配套综合判断。";
        };
        Map<String, Object> data = new HashMap<>();
        data.put("categoryCode", code);
        data.put("advice", advice);
        return Result.success(data);
    }

    /** 设施综合评分：GET /api/ai/facilityScore/{id} */
    @GetMapping("/facilityScore/{id}")
    public Result<Map<String, Object>> facilityScore(@PathVariable Integer id) {
        Facility facility = facilityMapper.selectById(id);
        if (facility == null) {
            throw new BizException("设施不存在，ID=" + id);
        }
        // 已审核用户评价平均分（0-5）转百分制
        double avg = facility.getAvgScore() == null ? 0 : facility.getAvgScore().doubleValue();
        double score100 = Math.round(avg / 5.0 * 100.0 * 10.0) / 10.0;
        String level = avg >= 4.0 ? "优秀" : avg >= 3.0 ? "良好" : avg >= 2.0 ? "一般" : "待提升";
        String advice = level.equals("待提升") || avg == 0
                ? "该设施暂未积累足够的已审核用户评价，建议实地考察后综合判断；也欢迎提交您的使用评价。"
                : "该设施用户评价良好（" + level + "），综合推荐指数较高，可放心前往体验。";

        Map<String, Object> data = new HashMap<>();
        data.put("facilityId", facility.getFacilityId());
        data.put("facilityName", facility.getFacilityName());
        data.put("categoryName", facility.getCategoryName());
        data.put("avgScore", avg);
        data.put("score100", score100);
        data.put("level", level);
        data.put("advice", advice);
        return Result.success(data);
    }

    /**
     * AI 综合分析：POST /api/ai/analysis
     * 入参: lng, lat, radius(米), categories(可选分类代码数组)
     * 返回: facilityCount 可达设施数 / communityCount 周边小区数
     *       avgPrice 周边小区平均房价 / score100 百分制综合评分(规则版)
     *       categoryStats 分类统计 / advice 智能建议 / aiEnabled 是否启用真实大模型
     */
    @PostMapping("/analysis")
    public Result<Map<String, Object>> analysis(@RequestBody Map<String, Object> body) {
        Double lng = Double.valueOf(String.valueOf(body.get("lng")));
        Double lat = Double.valueOf(String.valueOf(body.get("lat")));
        Integer radius = Integer.valueOf(String.valueOf(body.getOrDefault("radius", 1000)));
        @SuppressWarnings("unchecked")
        List<String> cats = (List<String>) body.getOrDefault("categories", new ArrayList<>());

        // 1. 缓冲区设施（可选按分类过滤）
        List<Facility> facilities = facilitySpatialService.listFacilityByPointBuffer(lng, lat, radius);
        if (cats != null && !cats.isEmpty()) {
            facilities = facilities.stream()
                    .filter(f -> cats.contains(f.getCategoryCode()))
                    .toList();
        }

        // 2. 周边小区
        List<Community> communities = communitySpatialService.listCommunityByPointBuffer(lng, lat, radius);

        // 3. 分类统计
        Map<String, Integer> categoryStats = new HashMap<>();
        facilities.forEach(f -> {
            String code = f.getCategoryCode();
            categoryStats.put(code, categoryStats.getOrDefault(code, 0) + 1);
        });

        // 4. 周边小区平均房价（有房价的小区）
        double avgPrice = communities.stream()
                .map(c -> c.getPrice() == null ? 0.0 : c.getPrice().doubleValue())
                .filter(v -> v > 0)
                .mapToDouble(v -> v)
                .average().orElse(0.0);
        avgPrice = Math.round(avgPrice);

        // 5. 综合评分（规则版：设施分类覆盖率 60% + 用户评价均分 40%）
        //    覆盖率 = 可达分类数 / 总分类数（真实统计，评价缺失时仍可评估配套完整度）
        double coverage = categoryStats.size() * 100.0 / Math.max(1, 7.0);
        double avgScore = facilities.stream()
                .map(f -> f.getAvgScore() == null ? 0.0 : f.getAvgScore().doubleValue())
                .filter(v -> v > 0)
                .mapToDouble(v -> v)
                .average().orElse(0.0);
        double score100 = Math.round((coverage * 0.6 + avgScore / 5.0 * 100.0 * 0.4) * 10.0) / 10.0;
        score100 = Math.min(100.0, Math.max(0.0, score100));

        // 6. AI 建议（配置了大模型则真实转发，否则规则版）
        String advice;
        boolean aiEnabled = aiUrl != null && !aiUrl.trim().isEmpty();
        if (aiEnabled) {
            String prompt = "你是社区生活圈规划助手。当前分析：起点(" + lng + "," + lat + ")半径" + radius
                    + "米内，可达设施" + facilities.size() + "个，周边小区" + communities.size()
                    + "个，小区平均房价" + avgPrice + "元/㎡，设施综合评分" + score100 + "分。"
                    + "请用60字以内给出该生活圈便利性评价与改善建议。";
            try {
                String reqBody = "{\"model\":\"" + (aiModel == null ? "" : aiModel)
                        + "\",\"messages\":[{\"role\":\"user\",\"content\":\"" + escapeJson(prompt) + "\"}]}";
                HttpRequest request = HttpRequest.newBuilder(URI.create(aiUrl.trim()))
                        .timeout(Duration.ofSeconds(30))
                        .header("Content-Type", "application/json;charset=UTF-8")
                        .header("Authorization", "Bearer " + (apiKey == null ? "" : apiKey))
                        .POST(HttpRequest.BodyPublishers.ofString(reqBody, StandardCharsets.UTF_8))
                        .build();
                HttpResponse<String> resp = HTTP.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
                String raw = resp.body();
                int idx = raw.indexOf("\"content\":\"");
                if (idx >= 0) {
                    String seg = raw.substring(idx + 11);
                    int end = seg.indexOf("\"");
                    advice = end > 0 ? seg.substring(0, end) : "AI 返回格式异常，请稍后重试。";
                } else {
                    advice = "AI 服务已响应但解析失败，可稍后重试。";
                }
            } catch (Exception e) {
                advice = "AI 服务调用失败（" + e.getMessage() + "），已切换为规则版建议。";
                aiEnabled = false;
            }
        } else {
            advice = coverage >= 85 ? "该区域生活圈配套完善，7类便民设施全覆盖，15分钟可达性高，宜居便利。"
                    : coverage >= 60 ? "该区域生活圈配套较均衡，已覆盖主要便民设施类别，可关注个别短板类别的补齐。"
                    : "该区域生活圈配套一般，覆盖类别较少，建议优先补齐医疗、商超等核心设施，提升可达性。";
        }

        Map<String, Object> data = new HashMap<>();
        data.put("facilityCount", facilities.size());
        data.put("communityCount", communities.size());
        data.put("avgPrice", avgPrice);
        data.put("score100", score100);
        data.put("categoryStats", categoryStats);
        data.put("advice", advice);
        data.put("aiEnabled", aiEnabled);
        return Result.success(data);
    }

    /** JSON 字符串转义（防止注入非法字符破坏请求体） */
    private String escapeJson(String s) {
        if (s == null) {
            return "";
        }
        StringBuilder sb = new StringBuilder();
        for (char c : s.toCharArray()) {
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                default -> sb.append(c);
            }
        }
        return sb.toString();
    }
}
