import React, { useState, useEffect, useCallback } from 'react';
import KoreaMap from './KoreaMap';
import { fetchWithRetry } from '../utils/fetchWithRetry';

const API_GATEWAY_URL = process.env.REACT_APP_API_GATEWAY_URL || '';

const DashboardPanel = ({ onNavigate, accidents, stats }) => {
  const [tollgateTop10, setTollgateTop10] = useState([]);
  const [routeTop12, setRouteTop12] = useState([]);
  const [lastUpdate, setLastUpdate] = useState(new Date());

  // Format date and time
  const formatDateTime = (accDate, accHour) => {
    if (!accDate || !accHour) return '';

    // accDate: YYYY.MM.DD or YYYYMMDD
    // accHour: HH:MM:SS or HHMM
    let formattedDate = accDate;
    let formattedTime = accHour;

    // If YYYYMMDD format, convert to YYYY.MM.DD
    if (accDate.length === 8 && !accDate.includes('.')) {
      const year = accDate.substring(0, 4);
      const month = accDate.substring(4, 6);
      const day = accDate.substring(6, 8);
      formattedDate = `${year}.${month}.${day}`;
    }

    // If HHMM format, convert to HH:MM
    if (accHour.length === 4 && !accHour.includes(':')) {
      const hour = accHour.substring(0, 2);
      const minute = accHour.substring(2, 4);
      formattedTime = `${hour}:${minute}`;
    }

    return `${formattedDate} ${formattedTime}`;
  };

  // Fetch tollgate traffic data and get top 10
  const fetchTollgateTop10 = useCallback(async () => {
    try {
      const response = await fetchWithRetry(`${API_GATEWAY_URL}/api/tollgate/traffic`, {
        timeout: 15000,
      }, 3);

      const data = await response.json();

      // Handle empty or null data
      if (!data || !Array.isArray(data) || data.length === 0) {
        setTollgateTop10([]);
        return;
      }

      // Sort by latest traffic amount and get top 6
      const sorted = data
        .map(tollgate => ({
          ...tollgate,
          latestAmount: tollgate.trafficData && tollgate.trafficData.length > 0
            ? tollgate.trafficData[0].trafficAmount
            : 0
        }))
        .sort((a, b) => b.latestAmount - a.latestAmount)
        .slice(0, 6);

      setTollgateTop10(sorted);
    } catch (err) {
      console.error('Failed to fetch tollgate data:', err);
      setTollgateTop10([]);
    }
  }, []);

  // Fetch route summary and get top 12
  const fetchRouteTop12 = useCallback(async () => {
    try {
      const response = await fetchWithRetry(`${API_GATEWAY_URL}/api/road/summary`, {
        timeout: 15000,
      }, 3);

      const data = await response.json();

      // Handle empty or null data
      if (!data || !Array.isArray(data) || data.length === 0) {
        setRouteTop12([]);
        return;
      }

      // Sort by average speed (descending) and get top 8
      const sorted = data
        .sort((a, b) => b.avgSpeed - a.avgSpeed)
        .slice(0, 8);

      setRouteTop12(sorted);
    } catch (err) {
      console.error('Failed to fetch route data:', err);
      setRouteTop12([]);
    }
  }, []);

  // Initial load and refresh
  useEffect(() => {
    fetchTollgateTop10();
    fetchRouteTop12();

    const interval = setInterval(() => {
      fetchTollgateTop10();
      fetchRouteTop12();
      setLastUpdate(new Date());
    }, 10000); // 10 seconds

    return () => clearInterval(interval);
  }, [fetchTollgateTop10, fetchRouteTop12]);

  // Get bar color based on traffic amount
  const getBarColor = (amount) => {
    if (amount >= 1200) return 'bg-gradient-to-r from-red-500 to-red-600';
    if (amount >= 900) return 'bg-gradient-to-r from-orange-500 to-orange-600';
    if (amount >= 600) return 'bg-gradient-to-r from-yellow-500 to-yellow-600';
    if (amount >= 300) return 'bg-gradient-to-r from-green-500 to-green-600';
    return 'bg-gradient-to-r from-blue-500 to-blue-600';
  };

  // Get grade badge
  const getGradeBadge = (sections) => {
    const total = sections.totalSections;
    const smoothPercent = total > 0 ? (sections.smoothSections / total) * 100 : 0;

    if (smoothPercent >= 90) {
      return { bg: 'bg-green-100', text: 'text-green-800', label: '원활', color: '#10b981' };
    } else if (smoothPercent >= 70) {
      return { bg: 'bg-yellow-100', text: 'text-yellow-800', label: '서행', color: '#f59e0b' };
    } else {
      return { bg: 'bg-red-100', text: 'text-red-800', label: '정체', color: '#ef4444' };
    }
  };

  // Get recent 3 accidents
  const recentAccidents = accidents.slice(0, 3);

  // Count by accident type
  const accidentCount = accidents.filter(acc => acc.accType === '사고').length;
  const breakdownCount = accidents.filter(acc => acc.accType === '고장').length;
  const workCount = accidents.filter(acc => acc.accType === '작업').length;
  const congestionCount = accidents.filter(acc => acc.accType && acc.accType.includes('정체')).length;

  return (
    <div className="rounded-lg p-4">
      {/* Overall Stats - Individual Cards */}
      {stats && (
        <div className="grid grid-cols-5 gap-3 mb-3">
          {/* Total Accidents */}
          <div className="bg-gradient-to-br from-slate-800/80 to-slate-800/50 backdrop-blur-sm rounded-xl border border-slate-700 p-4 hover:border-slate-600 transition-all shadow-lg">
            <div className="flex items-center justify-between mb-2">
              <span className="text-2xl">📊</span>
              <p className="text-xs font-medium text-slate-400">총 사고</p>
            </div>
            <p className="text-3xl font-bold text-white">{accidents.length}<span className="text-base font-normal text-slate-400 ml-1">건</span></p>
          </div>

          {/* Tollgates */}
          <div className="bg-gradient-to-br from-slate-800/80 to-slate-800/50 backdrop-blur-sm rounded-xl border border-slate-700 p-4 hover:border-slate-600 transition-all shadow-lg">
            <div className="flex items-center justify-between mb-2">
              <span className="text-2xl">🚗</span>
              <p className="text-xs font-medium text-slate-400">요금소</p>
            </div>
            <p className="text-3xl font-bold text-white">{stats.totalTollgates || 467}<span className="text-base font-normal text-slate-400 ml-1">개</span></p>
          </div>

          {/* Routes */}
          <div className="bg-gradient-to-br from-slate-800/80 to-slate-800/50 backdrop-blur-sm rounded-xl border border-slate-700 p-4 hover:border-slate-600 transition-all shadow-lg">
            <div className="flex items-center justify-between mb-2">
              <span className="text-2xl">🛣️</span>
              <p className="text-xs font-medium text-slate-400">노선</p>
            </div>
            <p className="text-3xl font-bold text-white">{routeTop12.length > 0 ? 67 : 0}<span className="text-base font-normal text-slate-400 ml-1">개</span></p>
          </div>

          {/* Average Speed */}
          <div className="bg-gradient-to-br from-slate-800/80 to-slate-800/50 backdrop-blur-sm rounded-xl border border-slate-700 p-4 hover:border-slate-600 transition-all shadow-lg">
            <div className="flex items-center justify-between mb-2">
              <span className="text-2xl">⚡</span>
              <p className="text-xs font-medium text-slate-400">평균속도</p>
            </div>
            <p className="text-3xl font-bold text-white">
              {routeTop12.length > 0
                ? (routeTop12.reduce((sum, r) => sum + r.avgSpeed, 0) / routeTop12.length).toFixed(1)
                : 0}<span className="text-base font-normal text-slate-400 ml-1">km/h</span>
            </p>
          </div>

          {/* Smooth Traffic */}
          <div className="bg-gradient-to-br from-slate-800/80 to-slate-800/50 backdrop-blur-sm rounded-xl border border-slate-700 p-4 hover:border-slate-600 transition-all shadow-lg">
            <div className="flex items-center justify-between mb-2">
              <span className="text-2xl">🟢</span>
              <p className="text-xs font-medium text-slate-400">원활</p>
            </div>
            <p className="text-3xl font-bold text-green-400">
              {routeTop12.length > 0
                ? Math.round((routeTop12.reduce((sum, r) => sum + r.smoothSections, 0) /
                    routeTop12.reduce((sum, r) => sum + r.totalSections, 0)) * 100)
                : 0}<span className="text-base font-normal text-slate-400 ml-1">%</span>
            </p>
          </div>
        </div>
      )}

      {/* Main Content - 2 Column Layout */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">

        {/* Left Column - Accidents */}
        <div>
          <div className="bg-slate-800/50 backdrop-blur-sm rounded-xl shadow-xl border border-slate-700 p-4">
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-lg font-bold text-white">🚨 교통사고 현황 ({accidents.length}건)</h2>
              <button
                onClick={() => onNavigate('accidents')}
                className="px-4 py-1.5 bg-blue-500 text-white text-xs font-medium rounded-lg hover:bg-blue-600 transition-colors shadow-sm"
              >
                상세보기 →
              </button>
            </div>

            {/* Mini Map */}
            <div className="mb-3" style={{ height: '350px' }}>
              <style>{`
                .dashboard-mini-map .leaflet-container {
                  height: 350px !important;
                  border-radius: 12px;
                  background: linear-gradient(to bottom right, #eff6ff, #ecfdf5) !important;
                }
                .dashboard-mini-map .leaflet-control-zoom {
                  display: none;
                }
              `}</style>
              <div className="dashboard-mini-map">
                <KoreaMap accidents={accidents.slice(0, 30)} miniMode={true} />
              </div>
            </div>

            {/* Stats by Type */}
            <div className="grid grid-cols-4 gap-2 mb-3">
              <div className="text-center p-2 bg-red-900/30 rounded-lg border border-red-800/50">
                <p className="text-lg font-bold text-red-400">🚨 {accidentCount}</p>
                <p className="text-xs text-slate-400">사고</p>
              </div>
              <div className="text-center p-2 bg-orange-900/30 rounded-lg border border-orange-800/50">
                <p className="text-lg font-bold text-orange-400">🔧 {breakdownCount}</p>
                <p className="text-xs text-slate-400">고장</p>
              </div>
              <div className="text-center p-2 bg-blue-900/30 rounded-lg border border-blue-800/50">
                <p className="text-lg font-bold text-blue-400">🚧 {workCount}</p>
                <p className="text-xs text-slate-400">작업</p>
              </div>
              <div className="text-center p-2 bg-yellow-900/30 rounded-lg border border-yellow-800/50">
                <p className="text-lg font-bold text-yellow-400">🚗 {congestionCount}</p>
                <p className="text-xs text-slate-400">정체</p>
              </div>
            </div>

            {/* Recent Accidents */}
            <div>
              <h3 className="text-sm font-semibold text-slate-300 mb-2">📋 최근 사고 3건</h3>
              <div className="space-y-2">
                {recentAccidents.map((acc, idx) => {
                  const dateTimeStr = formatDateTime(acc.accDate, acc.accHour);
                  // Extract time part only (after space)
                  const timeStr = dateTimeStr.split(' ')[1] || dateTimeStr;

                  // Get type badge
                  let typeBadge = { bg: 'bg-slate-700', text: 'text-slate-300', label: acc.accType || '정보없음' };
                  if (acc.accType === '사고') {
                    typeBadge = { bg: 'bg-red-900/50', text: 'text-red-300', label: '사고' };
                  } else if (acc.accType === '고장') {
                    typeBadge = { bg: 'bg-orange-900/50', text: 'text-orange-300', label: '고장' };
                  } else if (acc.accType === '작업') {
                    typeBadge = { bg: 'bg-blue-900/50', text: 'text-blue-300', label: '작업' };
                  } else if (acc.accType && acc.accType.includes('정체')) {
                    typeBadge = { bg: 'bg-yellow-900/50', text: 'text-yellow-300', label: '정체' };
                  }

                  return (
                    <div key={acc.id || idx} className="text-xs border-l-3 border-blue-500 bg-slate-700/30 pl-3 py-2 rounded-r">
                      <div className="flex items-start justify-between">
                        <div className="flex-1">
                          <span className="font-semibold text-white">
                            {timeStr}
                          </span>
                          <span className="ml-2 text-slate-300">{acc.roadNM}</span>
                          <span className={`ml-2 px-2 py-0.5 ${typeBadge.bg} ${typeBadge.text} rounded text-xs font-medium`}>
                            {typeBadge.label}
                          </span>
                        </div>
                      </div>
                      <p className="text-slate-400 mt-1">{acc.accInfo || acc.smsText || '상세 정보 없음'}</p>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
        </div>

        {/* Right Column */}
        <div className="space-y-3">

          {/* Top 6 Tollgates */}
          <div className="bg-slate-800/50 backdrop-blur-sm rounded-xl shadow-xl border border-slate-700 p-4">
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-lg font-bold text-white">🚗 요금소 교통량 Top 6</h2>
              <button
                onClick={() => onNavigate('tollgate')}
                className="px-4 py-1.5 bg-blue-500 text-white text-xs font-medium rounded-lg hover:bg-blue-600 transition-colors shadow-sm"
              >
                상세보기 →
              </button>
            </div>

            <div className="space-y-2.5">
              {tollgateTop10.map((tollgate, idx) => {
                const maxAmount = Math.max(...tollgateTop10.map(t => t.latestAmount));
                const width = (tollgate.latestAmount / maxAmount) * 100;

                return (
                  <div key={tollgate.unitCode} className="relative">
                    <div className="flex items-center justify-between text-sm mb-1">
                      <span className="font-semibold text-white">
                        {idx + 1}. {tollgate.unitName}
                      </span>
                      <span className="font-bold text-white">{tollgate.latestAmount}<span className="text-xs font-normal text-slate-400">대</span></span>
                    </div>
                    <div className="w-full bg-slate-700 rounded-full h-5 relative overflow-hidden border border-slate-600">
                      <div
                        className={`h-full ${getBarColor(tollgate.latestAmount)} transition-all duration-500 rounded-full shadow-sm`}
                        style={{ width: `${width}%` }}
                      ></div>
                    </div>
                  </div>
                );
              })}
            </div>

            {tollgateTop10.length > 0 && (
              <div className="mt-3 pt-3 border-t border-slate-700 text-center text-sm text-slate-400">
                평균: <span className="font-semibold text-white">{Math.round(tollgateTop10.reduce((sum, t) => sum + t.latestAmount, 0) / tollgateTop10.length)}</span>대
              </div>
            )}
          </div>

          {/* Top 8 Routes */}
          <div className="bg-slate-800/50 backdrop-blur-sm rounded-xl shadow-xl border border-slate-700 p-4">
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-lg font-bold text-white">🛣️ 노선별 소통 현황 Top 8</h2>
              <button
                onClick={() => onNavigate('roadstatus')}
                className="px-4 py-1.5 bg-blue-500 text-white text-xs font-medium rounded-lg hover:bg-blue-600 transition-colors shadow-sm"
              >
                상세보기 →
              </button>
            </div>

            <div className="grid grid-cols-4 gap-2.5">
              {routeTop12.map((route) => {
                const badge = getGradeBadge(route);
                return (
                  <div key={route.routeNo} className="text-center p-3 bg-slate-700/30 rounded-xl border border-slate-600 hover:shadow-lg hover:border-slate-500 transition-all">
                    <div className="relative inline-block mb-1.5">
                      <svg width="44" height="44" viewBox="0 0 50 50">
                        <circle
                          cx="25"
                          cy="25"
                          r="20"
                          fill="none"
                          stroke="#475569"
                          strokeWidth="5"
                        />
                        <circle
                          cx="25"
                          cy="25"
                          r="20"
                          fill="none"
                          stroke={badge.color}
                          strokeWidth="5"
                          strokeDasharray={`${(route.smoothSections / route.totalSections) * 125.6} 125.6`}
                          transform="rotate(-90 25 25)"
                          strokeLinecap="round"
                        />
                      </svg>
                      <div className="absolute inset-0 flex items-center justify-center">
                        <span className="text-sm font-bold text-white">{route.avgSpeed.toFixed(0)}</span>
                      </div>
                    </div>
                    <p className="text-xs font-semibold text-white truncate mb-1">{route.routeName}</p>
                    <span className={`inline-block px-2 py-0.5 ${badge.bg} ${badge.text} text-xs rounded-full font-medium`}>
                      {badge.label}
                    </span>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default DashboardPanel;
