package com.example.springboot.mapper;
import com.example.springboot.entity.AnalysisPlan;
import org.apache.ibatis.annotations.Delete;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Options;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

@Mapper
public interface AnalysisPlanMapper {
@Insert("INSERT INTO analysis_plan(user_id,plan_name,start_type,start_lon,start_lat,start_community_id,time_min,facility_types,weights,price_min) " +
        "VALUES(#{userId},#{planName},#{startType},#{startLon},#{startLat},#{startCommunityId},#{timeMin},#{facilityTypes},#{weights},#{priceMin})")
@Options(useGeneratedKeys = true, keyProperty = "id")
int insert(AnalysisPlan analysisPlan);

@Select("SELECT * FROM analysis_plan WHERE id = #{id}")
AnalysisPlan getPlanById(Integer id);

// 修改方案（实现移到XML文件，删掉@Update注解）
int updatePlan(AnalysisPlan analysisPlan);

// 删除方案
@Delete("DELETE FROM analysis_plan WHERE id=#{id}")
int deletePlan(Integer id);
}
