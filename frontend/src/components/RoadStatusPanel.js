import React, { useState, useEffect, useCallback } from 'react';

const API_GATEWAY_URL = process.env.REACT_APP_API_GATEWAY_URL || '';

const RoadStatusPanel = () => {
  const [roadStatuses, setRoadStatuses] = useState([]);
  const [error, setError] = useState(null);
  const [lastFetchTime, setLastFetchTime] = useState(null);
  const [filterRoute, setFilterRoute] = useState('all');

  // Fetch road status data
  const fetchRoadStatus = useCallback(async () => {
    try {
      const response = await fetch(`${API_GATEWAY_URL}/api/road/status`);

      if (!response.ok) {
        throw new Error(`API 연결 실패: ${response.status}`);
      }

      const data = await response.json();
      setRoadStatuses(data);
      setError(null);
      setLastFetchTime(new Date());
    } catch (err) {
      console.error('Failed to fetch road status:', err);
      setError(err.message);
    }
  }, []);

  // Auto-refresh every 5 minutes
  useEffect(() => {
    fetchRoadStatus();

    const interval = setInterval(() => {
      fetchRoadStatus();
    }, 5 * 60 * 1000); // 5 minutes

    return () => clearInterval(interval);
  }, [fetchRoadStatus]);

  // Get grade badge
  const getGradeBadge = (grade) => {
    switch (grade) {
      case 1: // 원활 (80km 이상)
        return { bg: 'bg-green-100', text: 'text-green-800', label: '원활' };
      case 2: // 서행 (40-80km)
        return { bg: 'bg-yellow-100', text: 'text-yellow-800', label: '서행' };
      case 3: // 정체 (0-40km)
        return { bg: 'bg-red-100', text: 'text-red-800', label: '정체' };
      default: // 판정불가
        return { bg: 'bg-gray-100', text: 'text-gray-800', label: '불가' };
    }
  };

  // Get speed color
  const getSpeedColor = (speed) => {
    if (speed >= 80) return 'text-green-600 font-semibold';
    if (speed >= 40) return 'text-yellow-600 font-semibold';
    return 'text-red-600 font-semibold';
  };

  // Get direction label
  const getDirectionLabel = (code) => {
    return code === 'S' ? '상행' : '하행';
  };

  // Get unique route list
  const routes = ['all', ...new Set(roadStatuses.map(rs => rs.routeName))];

  // Filter by route
  const filteredStatuses = filterRoute === 'all'
    ? roadStatuses
    : roadStatuses.filter(rs => rs.routeName === filterRoute);

  // Group by route for better organization
  const groupedByRoute = filteredStatuses.reduce((acc, rs) => {
    if (!acc[rs.routeName]) {
      acc[rs.routeName] = [];
    }
    acc[rs.routeName].push(rs);
    return acc;
  }, {});

  return (
    <div className="bg-gray-50 rounded-lg p-6">
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">고속도로 실시간 소통정보</h2>
          <p className="text-sm text-gray-500 mt-1">
            5분 단위 실시간 교통 소통 현황
          </p>
        </div>
        {lastFetchTime && (
          <div className="text-right">
            <p className="text-xs text-gray-400">최근 갱신</p>
            <p className="text-sm font-medium text-gray-700">
              {lastFetchTime.toLocaleTimeString('ko-KR')}
            </p>
          </div>
        )}
      </div>

      {/* Error Message */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 mb-6">
          <div className="flex items-center">
            <div className="ml-3">
              <h3 className="text-sm font-medium text-red-800">데이터 수집 실패</h3>
              <div className="mt-1 text-sm text-red-700">
                <p>{error}</p>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Filter */}
      <div className="mb-4 flex items-center gap-2">
        <span className="text-sm font-medium text-gray-700">노선:</span>
        <div className="flex flex-wrap gap-2">
          {routes.map(route => (
            <button
              key={route}
              onClick={() => setFilterRoute(route)}
              className={`px-3 py-1 text-sm rounded-full transition-colors ${
                filterRoute === route
                  ? 'bg-blue-500 text-white'
                  : 'bg-white text-gray-700 hover:bg-gray-100 border border-gray-300'
              }`}
            >
              {route === 'all' ? '전체' : route}
            </button>
          ))}
        </div>
        <div className="ml-auto text-sm text-gray-600">
          총 <span className="font-semibold text-gray-900">{filteredStatuses.length}</span>개 구간
        </div>
      </div>

      {/* Legend */}
      <div className="mb-4 flex items-center gap-4 text-xs">
        <span className="text-gray-600">소통등급:</span>
        <div className="flex items-center gap-1">
          <span className="px-2 py-1 rounded-full bg-green-100 text-green-800">원활</span>
          <span className="text-gray-400">80km+</span>
        </div>
        <div className="flex items-center gap-1">
          <span className="px-2 py-1 rounded-full bg-yellow-100 text-yellow-800">서행</span>
          <span className="text-gray-400">40-80km</span>
        </div>
        <div className="flex items-center gap-1">
          <span className="px-2 py-1 rounded-full bg-red-100 text-red-800">정체</span>
          <span className="text-gray-400">0-40km</span>
        </div>
      </div>

      {/* Road Status Table */}
      {roadStatuses.length === 0 && !error ? (
        <div className="text-center py-12 text-gray-400">
          데이터를 불러오는 중...
        </div>
      ) : (
        <div className="space-y-6">
          {Object.entries(groupedByRoute).map(([routeName, statuses]) => (
            <div key={routeName} className="bg-white rounded-lg shadow-sm overflow-hidden">
              <div className="bg-blue-50 px-4 py-2 border-b border-blue-100">
                <h3 className="font-semibold text-blue-900">{routeName}</h3>
                <p className="text-xs text-blue-600">{statuses.length}개 구간</p>
              </div>
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">구간명</th>
                      <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">방향</th>
                      <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">속도</th>
                      <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">교통량</th>
                      <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">소통등급</th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {statuses.map((status, idx) => {
                      const gradeBadge = getGradeBadge(status.grade);
                      return (
                        <tr key={idx} className="hover:bg-gray-50 transition-colors">
                          <td className="px-4 py-3 text-sm text-gray-900">{status.conzoneName}</td>
                          <td className="px-4 py-3 text-center text-sm text-gray-600">
                            {getDirectionLabel(status.updownTypeCode)}
                          </td>
                          <td className={`px-4 py-3 text-center text-sm ${getSpeedColor(status.speed)}`}>
                            {status.speed} km/h
                          </td>
                          <td className="px-4 py-3 text-center text-sm text-gray-900">
                            {status.trafficAmount} 대
                          </td>
                          <td className="px-4 py-3 text-center">
                            <span className={`inline-flex px-2 py-1 text-xs rounded-full ${gradeBadge.bg} ${gradeBadge.text}`}>
                              {gradeBadge.label}
                            </span>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default RoadStatusPanel;
