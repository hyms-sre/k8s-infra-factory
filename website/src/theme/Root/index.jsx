// =============================================================================
// Root — Docusaurus 全局根装饰器 (官方覆盖点, 不侵入原组件)
// 在全站渲染悬浮按钮组 (返回顶部 / 悬浮搜索)
// =============================================================================
import React from 'react';
import FloatingWidgets from '../../components/FloatingWidgets';

export default function Root({ children }) {
  return (
    <>
      {children}
      <FloatingWidgets />
    </>
  );
}
