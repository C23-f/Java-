package com.example.springboot.mapper;

import com.example.springboot.entity.District;
import org.apache.ibatis.annotations.Param;
import java.util.List;

public interface DistrictMapper {
    // 查询全部街道
    List<District> selectAll();

    // 根据ID查询街道
    District selectById(@Param("id") Integer id);

    // 新增街道
    int insert(District district);

    // 修改街道
    int update(District district);

    // 删除街道
    int deleteById(@Param("id") Integer id);
}
