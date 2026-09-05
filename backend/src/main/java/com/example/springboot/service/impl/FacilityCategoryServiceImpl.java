package com.example.springboot.service.impl;

import com.example.springboot.entity.FacilityCategory;
import com.example.springboot.mapper.FacilityCategoryMapper;
import com.example.springboot.service.FacilityCategoryService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import java.util.List;

/**
 * 设施分类 Service 实现类
 * 调用 Mapper 层查数据库，处理业务逻辑
 */
@Service
public class FacilityCategoryServiceImpl implements FacilityCategoryService {

    @Autowired
    private FacilityCategoryMapper facilityCategoryMapper;

    @Override
    public List<FacilityCategory> listAll() {
        // 调用 Mapper 查数据库，返回结果
        return facilityCategoryMapper.selectAll();
    }
    
        @Override
    public FacilityCategory getById(Integer id) {
        return facilityCategoryMapper.selectById(id);
    }
    @Override
    public int add(FacilityCategory category) {
        return facilityCategoryMapper.insert(category);
    }

    @Override
    public int edit(FacilityCategory category) {
        return facilityCategoryMapper.update(category);
    }

    @Override
    public int remove(Integer id) {
        return facilityCategoryMapper.deleteById(id);
    }


}
