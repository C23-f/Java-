package com.example.springboot.controller;

import com.example.springboot.common.Result;
import com.example.springboot.entity.District;
import com.example.springboot.service.DistrictService;
import jakarta.annotation.Resource;
import org.springframework.web.bind.annotation.*;
import java.util.List;

/**
 * 街道行政区 Controller
 * 查询接口（GET）公开访问（地图渲染街道边界、按街道筛选）；
 * 增删改（POST/PUT/DELETE）需 admin/operator 角色，由 JwtInterceptor 校验
 */
@RestController
@RequestMapping("/api/district")
public class DistrictController {

    @Resource
    private DistrictService districtService;

    // 街道列表（不含边界，用于下拉筛选）
    @GetMapping("/list")
    public Result<List<District>> list() {
        return Result.success(districtService.listAll());
    }

    // 街道详情（含边界GeoJSON，用于地图渲染）
    @GetMapping("/{id:\\d+}")
    public Result<District> getById(@PathVariable Integer id) {
        return Result.success(districtService.getById(id));
    }

    // 新增街道
    @PostMapping
    public Result<String> add(@RequestBody District district) {
        districtService.add(district);
        return Result.success("新增成功");
    }

    // 修改街道
    @PutMapping
    public Result<String> edit(@RequestBody District district) {
        districtService.edit(district);
        return Result.success("修改成功");
    }

    // 删除街道
    @DeleteMapping("/{id:\\d+}")
    public Result<String> remove(@PathVariable Integer id) {
        districtService.remove(id);
        return Result.success("删除成功");
    }
}
