package com.example.springboot.service.impl;

import com.example.springboot.common.BizException;
import com.example.springboot.entity.District;
import com.example.springboot.mapper.DistrictMapper;
import com.example.springboot.service.DistrictService;
import com.example.springboot.service.OperationLogService;
import jakarta.annotation.Resource;
import org.springframework.stereotype.Service;
import java.util.List;

@Service
public class DistrictServiceImpl implements DistrictService {

    @Resource
    private DistrictMapper districtMapper;
    @Resource
    private OperationLogService operationLogService;

    @Override
    public List<District> listAll() {
        return districtMapper.selectAll();
    }

    @Override
    public District getById(Integer id) {
        if (id == null) {
            throw new BizException("街道ID不能为空");
        }
        return districtMapper.selectById(id);
    }

    @Override
    public void add(District district) {
        if (district.getName() == null || district.getName().trim().isEmpty()) {
            throw new BizException("街道名称不能为空");
        }
        int rows = districtMapper.insert(district);
        if (rows <= 0) {
            throw new BizException("新增街道失败");
        }
        operationLogService.log("新增", "district", district.getId(),
                "新增街道：" + district.getName());
    }

    @Override
    public void edit(District district) {
        if (district.getId() == null) {
            throw new BizException("街道ID不能为空");
        }
        District exist = districtMapper.selectById(district.getId());
        if (exist == null) {
            throw new BizException("街道不存在，ID=" + district.getId());
        }
        if (district.getName() == null || district.getName().trim().isEmpty()) {
            throw new BizException("街道名称不能为空");
        }
        int rows = districtMapper.update(district);
        if (rows <= 0) {
            throw new BizException("修改街道失败");
        }
        operationLogService.log("修改", "district", district.getId(),
                "修改街道：" + district.getName());
    }

    @Override
    public void remove(Integer id) {
        if (id == null) {
            throw new BizException("街道ID不能为空");
        }
        District exist = districtMapper.selectById(id);
        if (exist == null) {
            throw new BizException("街道不存在，ID=" + id);
        }
        int rows = districtMapper.deleteById(id);
        if (rows <= 0) {
            throw new BizException("删除街道失败");
        }
        operationLogService.log("删除", "district", id,
                "删除街道：" + exist.getName());
    }
}
