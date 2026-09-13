package com.example.springboot.service;

import com.example.springboot.entity.District;
import java.util.List;

public interface DistrictService {
    // 查询全部街道（不含边界，列表用）
    List<District> listAll();

    // 根据ID查询街道（含边界GeoJSON）
    District getById(Integer id);

    // 新增街道
    void add(District district);

    // 修改街道
    void edit(District district);

    // 删除街道
    void remove(Integer id);
}
