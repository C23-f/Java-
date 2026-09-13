package com.example.springboot.controller;

import com.example.springboot.common.BizException;
import com.example.springboot.common.Result;
import com.example.springboot.mapper.CommunityMapper;
import com.example.springboot.mapper.FacilityMapper;
import jakarta.annotation.Resource;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import java.util.HashMap;
import java.util.Map;

/**
 * 全局模糊搜索 Controller
 * GET /api/search?keyword=xxx  →  同时返回匹配的小区列表与设施列表
 */
@RestController
@RequestMapping("/api/search")
public class SearchController {

    @Resource
    private CommunityMapper communityMapper;
    @Resource
    private FacilityMapper facilityMapper;

    @GetMapping
    public Result<Map<String, Object>> search(@RequestParam String keyword) {
        if (keyword == null || keyword.trim().isEmpty()) {
            throw new BizException("搜索关键字不能为空");
        }
        String kw = keyword.trim();
        Map<String, Object> data = new HashMap<>();
        data.put("communities", communityMapper.searchCommunities(kw));
        data.put("facilities", facilityMapper.searchFacilities(kw));
        return Result.success(data);
    }
}
