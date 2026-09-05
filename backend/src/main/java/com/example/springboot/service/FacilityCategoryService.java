package com.example.springboot.service;

import com.example.springboot.entity.FacilityCategory;
import java.util.List;

/**
 * 设施分类 Service 接口（业务逻辑层）
 */
public interface FacilityCategoryService {

    /** 获取所有设施分类列表 */
    List<FacilityCategory> listAll();
    FacilityCategory getById(Integer id);
    //新增
    int add(FacilityCategory category);
    //修改
    int edit(FacilityCategory category);
    //删除
    int remove(Integer id);

}
