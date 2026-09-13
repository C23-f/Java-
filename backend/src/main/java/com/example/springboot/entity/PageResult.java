package com.example.springboot.entity;

import lombok.Data;
import java.util.List;

/**
 * 通用分页返回结果
 * @param <T> 列表元素类型
 */
@Data
public class PageResult<T> {
    /** 总记录数 */
    private Long total;
    /** 当前页数据 */
    private List<T> list;
    /** 当前页码（从1开始） */
    private Integer pageNum;
    /** 每页条数 */
    private Integer pageSize;

    public static <T> PageResult<T> of(Long total, List<T> list, Integer pageNum, Integer pageSize) {
        PageResult<T> result = new PageResult<>();
        result.setTotal(total);
        result.setList(list);
        result.setPageNum(pageNum);
        result.setPageSize(pageSize);
        return result;
    }
}
