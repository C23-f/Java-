package com.example.springboot.mapper;

import com.example.springboot.entity.FacilityCategory;
import org.apache.ibatis.annotations.Mapper;
import java.util.List;

/**
 * 设施分类 Mapper 接口（数据访问层）
 * 只定义方法，SQL 写在对应的 XML 文件里
 */
@Mapper
public interface FacilityCategoryMapper {

    /** 查询所有设施分类，按排序号排列 */
    List<FacilityCategory> selectAll();
}
