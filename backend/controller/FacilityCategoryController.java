package com.example.springboot.controller;

import com.example.springboot.common.Result;
import com.example.springboot.entity.FacilityCategory;
import com.example.springboot.service.FacilityCategoryService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import java.util.List;

/**
 * 设施分类 Controller（接口层）
 * 前端通过 HTTP 请求访问这里，返回 JSON 数据
 *
 * 访问地址：http://localhost:9090/api/category/list
 */
@RestController
@RequestMapping("/api/category")
public class FacilityCategoryController {

    @Autowired
    private FacilityCategoryService facilityCategoryService;

    /**
     * 查询所有设施分类
     * 请求方式：GET
     * 完整路径：/api/category/list
     */
    @GetMapping("/list")
    public Result<List<FacilityCategory>> list() {
        List<FacilityCategory> list = facilityCategoryService.listAll();
        return Result.success(list);
    }
}
