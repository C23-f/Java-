package com.example.springboot.service.impl;

import com.example.springboot.common.BizException;
import com.example.springboot.entity.AccessibilityScore;
import com.example.springboot.entity.Community;
import com.example.springboot.entity.CommunityStatsVO;
import com.example.springboot.entity.SpatialCircleVO;
import com.example.springboot.mapper.CommunityMapper;
import com.example.springboot.service.CommunitySpatialService;
import org.springframework.stereotype.Service;
import jakarta.annotation.Resource;
import java.util.ArrayList;
import java.util.List;

@Service
public class CommunitySpatialServiceImpl implements CommunitySpatialService {

    @Resource
    private CommunityMapper communityMapper;

    @Override
    public List<Community> listAllCommunity() {
        return communityMapper.selectAllCommunity();
    }

    @Override
    public Community getById(Integer id) {
        if (id == null) {
            throw new BizException("小区ID不能为空");
        }
        return communityMapper.selectById(id);
    }

    @Override
    public void add(Community community) {
        // 非空校验
        if (community.getCommunityName() == null || community.getCommunityName().trim().isEmpty()) {
            throw new BizException("小区名称不能为空");
        }
        // 经纬度范围校验
        validateLngLat(community.getLongitude(), community.getLatitude());
        // 步行速度默认值
        if (community.getWalkSpeed() == null) {
            community.setWalkSpeed(1.2);
        }
        int rows = communityMapper.insert(community);
        if (rows <= 0) {
            throw new BizException("新增小区失败");
        }
    }

    @Override
    public void edit(Community community) {
        if (community.getCommunityId() == null) {
            throw new BizException("小区ID不能为空");
        }
        // 存在性校验
        Community exist = communityMapper.selectById(community.getCommunityId());
        if (exist == null) {
            throw new BizException("小区不存在，ID=" + community.getCommunityId());
        }
        if (community.getCommunityName() == null || community.getCommunityName().trim().isEmpty()) {
            throw new BizException("小区名称不能为空");
        }
        validateLngLat(community.getLongitude(), community.getLatitude());
        int rows = communityMapper.update(community);
        if (rows <= 0) {
            throw new BizException("修改小区失败");
        }
    }

    @Override
    public void remove(Integer id) {
        if (id == null) {
            throw new BizException("小区ID不能为空");
        }
        Community exist = communityMapper.selectById(id);
        if (exist == null) {
            throw new BizException("小区不存在，ID=" + id);
        }
        int rows = communityMapper.deleteById(id);
        if (rows <= 0) {
            throw new BizException("删除小区失败");
        }
    }

    /** 经纬度合法范围校验 */
    private void validateLngLat(Double lng, Double lat) {
        if (lng == null || lat == null) {
            throw new BizException("经度和纬度不能为空");
        }
        if (lng < -180 || lng > 180) {
            throw new BizException("经度不合法，有效范围 -180 ~ 180");
        }
        if (lat < -90 || lat > 90) {
            throw new BizException("纬度不合法，有效范围 -90 ~ 90");
        }
    }

    @Override
    public List<CommunityStatsVO> getCommunity15MinStats(Integer communityId, Integer radiusM) {
        return communityMapper.callStatsProc(communityId, radiusM);
    }

    @Override
    public AccessibilityScore calcSingleScore(Integer communityId, Integer radiusM, Integer perCategoryCap) {
        return communityMapper.callCalcScoreProc(communityId, radiusM, perCategoryCap);
    }

    @Override
    public List<AccessibilityScore> batchCalcAllCommunity(Integer radiusM, Integer perCategoryCap) {
        List<Community> communityList = communityMapper.selectAllCommunity();
        List<AccessibilityScore> resultList = new ArrayList<>();
        for (Community community : communityList) {
            AccessibilityScore score = communityMapper.callCalcScoreProc(community.getCommunityId(), radiusM, perCategoryCap);
            if (score != null) {
                resultList.add(score);
            }
        }
        return resultList;
    }
    @Override
    public List<SpatialCircleVO> getCommunityCircleData(Long communityId, Integer bufferMeter) {
    return communityMapper.getCommunitySpatialCircle(communityId, bufferMeter);
    }

}
