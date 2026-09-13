package com.example.springboot.mapper;
import com.example.springboot.entity.Evaluation;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import java.util.List;


@Mapper
public interface EvaluationMapper {
    int auditEvaluation(
            @Param("id") Integer id,
            @Param("status") Integer status,
            @Param("rejectReason") String rejectReason,
            @Param("auditorId") Integer auditorId
    );
    int insert(Evaluation evaluation);

    // 新增这一行
    List<Evaluation> selectEvaluationList(@Param("status") Integer status);
    // 根据id查询评价详情
    Evaluation selectById(Integer id);
    // 删除评价
    int deleteById(Integer id);
        // 查询当前登录用户自己提交的评价列表
    List<Evaluation> selectMyEvaluationList(@Param("userId") Integer userId);

    // 获取评价统计（图表接口，返回map）
    java.util.Map<String,Object> getEvaluationStats();

    // ==================== 分页 + 平均分联动（新增） ====================

    // 分页查询评价（status可选：0待审核 1通过 2驳回；不传查全部）
    List<Evaluation> selectEvaluationPage(@Param("status") Integer status,
                                          @Param("offset") Integer offset,
                                          @Param("limit") Integer limit);

    // 分页统计评价总数
    Long countEvaluation(@Param("status") Integer status);

    // 审核后重算对象平均分（objectType=community/facility，只统计已通过评价）
    int updateAvgScoreByObject(@Param("objectType") String objectType,
                               @Param("objectId") Integer objectId);

}
