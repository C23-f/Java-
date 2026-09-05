package com.example.springboot.mapper;

import com.example.springboot.entity.FacilityCategory;
import org.apache.ibatis.annotations.Mapper;
import java.util.List;

@Mapper
public interface FacilityCategoryMapper {
    List<FacilityCategory> selectAll();

    FacilityCategory selectById(Integer id);
    //新增
    int insert(FacilityCategory category);
    //修改
    int update(FacilityCategory category);
    //删除
    int deleteById(Integer categoryId);

}
