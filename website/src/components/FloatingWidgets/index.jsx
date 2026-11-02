// =============================================================================
// FloatingWidgets — 右下角悬浮按钮组
//   ▲ 返回顶部: 滚动超过 400px 浮现, 平滑滚回
//   🔍 悬浮搜索: 弹出搜索面板 (复用 @theme/SearchBar, 即离线中文搜索)
// =============================================================================
import React, { useCallback, useEffect, useRef, useState } from 'react';
import SearchBar from '@theme/SearchBar';

const BACK_TO_TOP_THRESHOLD = 400;

function ChevronUpIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"
      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M6 14l6-6 6 6" />
    </svg>
  );
}

function SearchIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"
      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <circle cx="11" cy="11" r="7" />
      <path d="M20 20l-3.5-3.5" />
    </svg>
  );
}

export default function FloatingWidgets() {
  const [showBackToTop, setShowBackToTop] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const panelRef = useRef(null);
  const searchBtnRef = useRef(null);

  // 返回顶部: 滚动显隐
  useEffect(() => {
    const onScroll = () => setShowBackToTop(window.scrollY > BACK_TO_TOP_THRESHOLD);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  const scrollToTop = useCallback(() => {
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }, []);

  // 搜索面板: ESC / 点击面板外关闭; 打开时聚焦输入框
  useEffect(() => {
    if (!searchOpen) return undefined;
    const onKey = (e) => {
      if (e.key === 'Escape') setSearchOpen(false);
    };
    const onMouseDown = (e) => {
      if (!panelRef.current?.contains(e.target) && !searchBtnRef.current?.contains(e.target)) {
        setSearchOpen(false);
      }
    };
    document.addEventListener('keydown', onKey);
    document.addEventListener('mousedown', onMouseDown);
    return () => {
      document.removeEventListener('keydown', onKey);
      document.removeEventListener('mousedown', onMouseDown);
    };
  }, [searchOpen]);

  useEffect(() => {
    if (searchOpen) panelRef.current?.querySelector('input')?.focus();
  }, [searchOpen]);

  return (
    <>
      {/* 遮罩层: 点击任意空白处关闭搜索面板 (z-index 400, 按钮组在其之上) */}
      {searchOpen && (
        <div
          className="floating-mask"
          onClick={() => setSearchOpen(false)}
          aria-hidden="true"
        />
      )}
      <div className="floating-widgets">
        {searchOpen && (
          <div className="floating-search" ref={panelRef}>
            <SearchBar />
          </div>
        )}
        {showBackToTop && (
          <button
            type="button"
            className="floating-btn"
            title="返回顶部"
            aria-label="返回顶部"
            onClick={scrollToTop}
          >
            <ChevronUpIcon />
          </button>
        )}
        <button
          type="button"
          ref={searchBtnRef}
          className={`floating-btn${searchOpen ? ' floating-btn--active' : ''}`}
          title="搜索"
          aria-label="搜索"
          onClick={() => setSearchOpen((o) => !o)}
        >
          <SearchIcon />
        </button>
      </div>
    </>
  );
}
