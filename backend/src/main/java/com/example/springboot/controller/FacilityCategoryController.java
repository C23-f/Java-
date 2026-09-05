package com.example.springboot.controller;

import com.example.springboot.common.Result;
import com.example.springboot.entity.FacilityCategory;
import com.example.springboot.service.FacilityCategoryService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
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
        // 根据ID查询单个分类
    @GetMapping("/{id}")
    public Result getById(@PathVariable Integer id) {
        FacilityCategory category = facilityCategoryService.getById(id);
        return Result.success(category);
    }
    //新增
    @PostMapping
    public Result add(@RequestBody FacilityCategory category){
        int res = facilityCategoryService.add(category);
        if(res>0){
            return Result.success("新增成功");
        }else {
            return Result.fail("新增失败");
        }
    }

    //修改
    @PutMapping
    public Result edit(@RequestBody FacilityCategory category){
        int res = facilityCategoryService.edit(category);
        if(res>0){
            return Result.success("修改成功");
        }else {
            return Result.fail("修改失败");
        }
    }

    //删除
    @DeleteMapping("/{id}")
    public Result remove(@PathVariable Integer id){
        int res = facilityCategoryService.remove(id);
        if(res>0){
            return Result.success("删除成功");
        }else {
            return Result.fail("删除失败");
        }
    }


}
