import React, { useState, useEffect, useCallback, useRef } from 'react';
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from 'recharts';
import { fetchWithRetry } from '../utils/fetchWithRetry';
import { healthMonitor } from '../utils/healthCheck';

const API_GATEWAY_URL = process.env.REACT_APP_API_GATEWAY_URL || '';

// Animated number component
const AnimatedNumber = ({ value, duration = 1000, decimals = 0 }) => {
  const [displayValue, setDisplayValue] = useState(0);
  const startTimeRef = useRef(null);
  const startValueRef = useRef(0);
  const targetValueRef = useRef(value);
  const animationFrameRef = useRef(null);

  useEffect(() => {
    startValueRef.current = displayValue;
    targetValueRef.current = value;
    startTimeRef.current = Date.now();

    const animate = () => {
      const now = Date.now();
      const elapsed = now - startTimeRef.current;
      const progress = Math.min(elapsed / duration, 1);

      // Ease-out cubic
      const easeProgress = 1 - Math.pow(1 - progress, 3);

      const current = startValueRef.current + (targetValueRef.current - startValueRef.current) * easeProgress;
      setDisplayValue(current);

      if (progress < 1) {
        animationFrameRef.current = requestAnimationFrame(animate);
      }
    };

    animationFrameRef.current = requestAnimationFrame(animate);

    return () => {
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current);
      }
    };
  }, [value, duration]);

  return <>{displayValue.toFixed(decimals)}</>;
};

// Route Card Component with Donut Chart
const RouteCard = ({ route, isUpdating, delay }) => {
  const [showContent, setShowContent] = useState(false);
  const [isHovered, setIsHovered] = useState(false);
  const [displaySpeed, setDisplaySpeed] = useState(route.avgSpeed);

  useEffect(() => {
    const timer = setTimeout(() => {
      setShowContent(true);
    }, delay);

    return () => clearTimeout(timer);
  }, [delay, route]);

  // When updating, reset speed to 0 and animate to actual value
  useEffect(() => {
    if (isUpdating) {
      setDisplaySpeed(0);
      // After a brief moment, animate to real speed
      setTimeout(() => {
        setDisplaySpeed(route.avgSpeed);
      }, 100);
    }
  }, [isUpdating, route.avgSpeed]);

  // Calculate percentages for donut chart
  const smoothPercent = route.totalSections > 0
    ? Math.round((route.smoothSections / route.totalSections) * 100)
    : 0;
  const slowPercent = route.totalSections > 0
    ? Math.round((route.slowSections / route.totalSections) * 100)
    : 0;
  const congestedPercent = route.totalSections > 0
    ? Math.round((route.congestedSections / route.totalSections) * 100)
    : 0;

  const chartData = [
    { name: '원활', value: route.smoothSections, color: '#10b981', percent: smoothPercent },
    { name: '서행', value: route.slowSections, color: '#f59e0b', percent: slowPercent },
    { name: '정체', value: route.congestedSections, color: '#ef4444', percent: congestedPercent },
  ].filter(item => item.value > 0);

  // Custom tooltip
  const CustomTooltip = ({ active, payload }) => {
    if (active && payload && payload.length) {
      return (
        <div className="bg-slate-800 border border-slate-600 rounded shadow-xl p-1.5 backdrop-blur-sm">
          <p className="text-[10px] text-slate-300 mb-0.5">총 구간: {route.totalSections}개</p>
          <div className="space-y-0.5">
            {chartData.map((item, index) => (
              <div key={index} className="flex items-center justify-between text-[10px]">
                <div className="flex items-center">
                  <div className="w-1.5 h-1.5 rounded-full mr-1" style={{ backgroundColor: item.color }}></div>
                  <span className="text-slate-400">{item.name}</span>
                </div>
                <span className="ml-1.5 font-semibold text-white">{item.value}개 ({item.percent}%)</span>
              </div>
            ))}
          </div>
        </div>
      );
    }
    return null;
  };

  return (
    <div
      className={`bg-slate-800/70 backdrop-blur-sm rounded-lg shadow-lg border-2 transition-all duration-500 ${
        isUpdating ? 'border-blue-500 shadow-xl shadow-blue-500/30 scale-105' : 'border-slate-700 hover:border-slate-600'
      }`}
      style={{
        opacity: showContent ? 1 : 0,
        transform: showContent ? 'translateY(0)' : 'translateY(20px)',
        transition: `opacity 0.5s ease-out ${delay}ms, transform 0.5s ease-out ${delay}ms`
      }}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
    >
      <div className="p-2">
        {/* Header */}
        <div className="text-center mb-1">
          <h3 className="text-xs font-bold text-white">{route.routeName}</h3>
        </div>

        {/* Donut Chart with Average Speed */}
        <div className="relative" style={{ height: '90px' }}>
          <ResponsiveContainer width="100%" height="100%">
            <PieChart>
              <Pie
                data={chartData}
                cx="50%"
                cy="50%"
                innerRadius={25}
                outerRadius={38}
                paddingAngle={2}
                dataKey="value"
                animationBegin={delay}
                animationDuration={800}
                stroke="none"
              >
                {chartData.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={entry.color} stroke="none" />
                ))}
              </Pie>
              <Tooltip content={<CustomTooltip />} />
            </PieChart>
          </ResponsiveContainer>

          {/* Center Text - Average Speed (hidden when hovered) */}
          {!isHovered && (
            <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
              <div className="text-center">
                <div className="text-xl font-bold text-white">
                  <AnimatedNumber value={displaySpeed} decimals={1} duration={800} />
                </div>
                <div className="text-xs text-slate-400">km/h</div>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Update indicator */}
      {isUpdating && (
        <div className="absolute top-2 right-2">
          <div className="w-2 h-2 rounded-full bg-blue-400 animate-pulse shadow-lg shadow-blue-400/50"></div>
        </div>
      )}
    </div>
  );
};

const RoadRouteSummaryPanel = () => {
  const [routes, setRoutes] = useState([]);
  const [updatingRoutes, setUpdatingRoutes] = useState(new Set());
  const [error, setError] = useState(null);
  const [lastFetchTime, setLastFetchTime] = useState(null);
  const [totalStats, setTotalStats] = useState(null);

  const fetchRouteSummary = useCallback(async () => {
    try {
      const response = await fetchWithRetry(`${API_GATEWAY_URL}/api/road/summary`, {
        timeout: 15000, // 15 second timeout
      }, 3); // Retry 3 times

      const data = await response.json();

      // Handle empty or null data
      if (!data || !Array.isArray(data) || data.length === 0) {
        // Don't clear data during cluster transition
        if (!healthMonitor.isTransitioning) {
          setRoutes([]);
          setError(null);
          setLastFetchTime(new Date());
          setTotalStats({
            totalRoutes: 0,
            totalSections: 0,
            smoothSections: 0,
            slowSections: 0,
            congestedSections: 0,
            avgSpeed: 0
          });
        }
        return;
      }

      // Silently update data without animation
      setRoutes(data);
      setError(null);
      setLastFetchTime(new Date());

      // Calculate total statistics
      const stats = {
        totalRoutes: data.length,
        totalSections: data.reduce((sum, r) => sum + r.totalSections, 0),
        smoothSections: data.reduce((sum, r) => sum + r.smoothSections, 0),
        slowSections: data.reduce((sum, r) => sum + r.slowSections, 0),
        congestedSections: data.reduce((sum, r) => sum + r.congestedSections, 0),
        avgSpeed: data.length > 0
          ? (data.reduce((sum, r) => sum + r.avgSpeed, 0) / data.length).toFixed(1)
          : 0
      };
      setTotalStats(stats);

    } catch (err) {
      console.error('Failed to fetch route summary:', err);
      // Don't clear data during cluster transition
      if (!healthMonitor.isTransitioning) {
        setRoutes([]);
        setError(null);
      }
    }
  }, []);

  // Simulate continuous real-time updates by randomly animating routes
  useEffect(() => {
    if (routes.length === 0) return;

    let timeoutId;

    const animateRandomRoutes = () => {
      // Pick 2-4 random routes to animate
      const numToAnimate = Math.floor(Math.random() * 3) + 2; // 2-4 routes
      const shuffled = [...routes].sort(() => Math.random() - 0.5);
      const selected = shuffled.slice(0, numToAnimate);

      selected.forEach((route, index) => {
        setTimeout(() => {
          setUpdatingRoutes(prev => new Set([...prev, route.routeNo]));

          // Remove update indicator after animation
          setTimeout(() => {
            setUpdatingRoutes(prev => {
              const newSet = new Set(prev);
              newSet.delete(route.routeNo);
              return newSet;
            });
          }, 1500);
        }, index * 200);
      });

      // Schedule next animation with random delay (6-9 seconds)
      const nextDelay = Math.random() * 3000 + 6000;
      timeoutId = setTimeout(animateRandomRoutes, nextDelay);
    };

    // Start first animation after initial load (3 seconds delay)
    timeoutId = setTimeout(animateRandomRoutes, 3000);

    return () => {
      if (timeoutId) clearTimeout(timeoutId);
    };
  }, [routes]);

  // Initial load and periodic refresh
  useEffect(() => {
    fetchRouteSummary(); // Initial load

    // Refresh every 5 minutes (silently)
    const interval = setInterval(() => {
      fetchRouteSummary();
    }, 5 * 60 * 1000);

    return () => clearInterval(interval);
  }, [fetchRouteSummary]);

  return (
    <div className="rounded-lg p-6">
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-white">실시간 도로 소통정보</h2>
          <p className="text-sm text-slate-400 mt-1">
            5분 단위 실시간 고속도로 소통 모니터링
          </p>
        </div>
        {lastFetchTime && (
          <div className="text-right">
            <p className="text-xs text-slate-500">최근 갱신</p>
            <p className="text-sm font-medium text-slate-300">
              {lastFetchTime.toLocaleTimeString('ko-KR')}
            </p>
          </div>
        )}
      </div>

      {/* Error Message */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 mb-6">
          <div className="flex items-center">
            <div className="flex-shrink-0">
              <svg className="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clipRule="evenodd" />
              </svg>
            </div>
            <div className="ml-3">
              <h3 className="text-sm font-medium text-red-800">데이터 수집 실패</h3>
              <div className="mt-1 text-sm text-red-700">
                <p>{error}</p>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Total Statistics Summary - Individual Cards */}
      {totalStats && (
        <div className="grid grid-cols-6 gap-3 mb-3">
          {/* Total Routes */}
          <div className="bg-gradient-to-br from-slate-800/80 to-slate-800/50 backdrop-blur-sm rounded-xl border border-slate-700 p-4 hover:border-slate-600 transition-all shadow-lg">
            <p className="text-xs font-medium text-slate-400 mb-2">총 노선</p>
            <p className="text-2xl font-bold text-white">
              <AnimatedNumber value={totalStats.totalRoutes} duration={1000} />
              <span className="text-sm font-normal text-slate-400 ml-1">개</span>
            </p>
          </div>

          {/* Total Sections */}
          <div className="bg-gradient-to-br from-slate-800/80 to-slate-800/50 backdrop-blur-sm rounded-xl border border-slate-700 p-4 hover:border-slate-600 transition-all shadow-lg">
            <p className="text-xs font-medium text-slate-400 mb-2">총 구간</p>
            <p className="text-2xl font-bold text-white">
              <AnimatedNumber value={totalStats.totalSections} duration={1000} />
              <span className="text-sm font-normal text-slate-400 ml-1">개</span>
            </p>
          </div>

          {/* Average Speed */}
          <div className="bg-gradient-to-br from-slate-800/80 to-slate-800/50 backdrop-blur-sm rounded-xl border border-slate-700 p-4 hover:border-slate-600 transition-all shadow-lg">
            <p className="text-xs font-medium text-slate-400 mb-2">평균 속도</p>
            <p className="text-2xl font-bold text-white">
              <AnimatedNumber value={parseFloat(totalStats.avgSpeed)} decimals={1} duration={1000} />
              <span className="text-sm font-normal text-slate-400 ml-1">km/h</span>
            </p>
          </div>

          {/* Smooth Sections */}
          <div className="bg-gradient-to-br from-slate-800/80 to-slate-800/50 backdrop-blur-sm rounded-xl border border-slate-700 p-4 hover:border-slate-600 transition-all shadow-lg">
            <p className="text-xs font-medium text-slate-400 mb-2">원활</p>
            <p className="text-2xl font-bold text-green-400">
              <AnimatedNumber value={totalStats.smoothSections} duration={1000} />
              <span className="text-sm font-normal text-slate-400 ml-1">
                ({totalStats.totalSections > 0
                  ? Math.round((totalStats.smoothSections / totalStats.totalSections) * 100)
                  : 0}%)
              </span>
            </p>
          </div>

          {/* Slow Sections */}
          <div className="bg-gradient-to-br from-slate-800/80 to-slate-800/50 backdrop-blur-sm rounded-xl border border-slate-700 p-4 hover:border-slate-600 transition-all shadow-lg">
            <p className="text-xs font-medium text-slate-400 mb-2">서행</p>
            <p className="text-2xl font-bold text-yellow-400">
              <AnimatedNumber value={totalStats.slowSections} duration={1000} />
              <span className="text-sm font-normal text-slate-400 ml-1">
                ({totalStats.totalSections > 0
                  ? Math.round((totalStats.slowSections / totalStats.totalSections) * 100)
                  : 0}%)
              </span>
            </p>
          </div>

          {/* Congested Sections */}
          <div className="bg-gradient-to-br from-slate-800/80 to-slate-800/50 backdrop-blur-sm rounded-xl border border-slate-700 p-4 hover:border-slate-600 transition-all shadow-lg">
            <p className="text-xs font-medium text-slate-400 mb-2">정체</p>
            <p className="text-2xl font-bold text-red-400">
              <AnimatedNumber value={totalStats.congestedSections} duration={1000} />
              <span className="text-sm font-normal text-slate-400 ml-1">
                ({totalStats.totalSections > 0
                  ? Math.round((totalStats.congestedSections / totalStats.totalSections) * 100)
                  : 0}%)
              </span>
            </p>
          </div>
        </div>
      )}

      {/* Route Cards Grid - 12 columns */}
      {routes.length === 0 && !error ? (
        <div className="text-center py-12">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500 mx-auto mb-4"></div>
          <p className="text-gray-500">데이터 로딩 중...</p>
        </div>
      ) : (
        <>
          <div className="mb-4 flex items-center justify-between">
            <p className="text-sm text-slate-400">
              총 <span className="font-semibold text-white">{routes.length}</span>개 노선
            </p>
            {updatingRoutes.size > 0 && (
              <div className="flex items-center gap-2">
                <div className="w-2 h-2 rounded-full bg-blue-400 animate-pulse shadow-lg shadow-blue-400/50"></div>
                <span className="text-xs text-slate-400">순차 업데이트 중</span>
              </div>
            )}
          </div>

          <div className="grid grid-cols-1 md:grid-cols-6 lg:grid-cols-12 gap-3">
            {routes.map((route, index) => (
              <RouteCard
                key={route.routeNo}
                route={route}
                isUpdating={updatingRoutes.has(route.routeNo)}
                delay={index * 10}
              />
            ))}
          </div>
        </>
      )}
    </div>
  );
};

export default RoadRouteSummaryPanel;
