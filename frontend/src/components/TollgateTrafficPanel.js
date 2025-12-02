import React, { useState, useEffect, useCallback, useRef } from 'react';
import TollgateCard from './TollgateCard';

const API_GATEWAY_URL = process.env.REACT_APP_API_GATEWAY_URL || '';

const TollgateTrafficPanel = () => {
  const [tollgates, setTollgates] = useState([]);
  const [loadingStates, setLoadingStates] = useState({});
  const [error, setError] = useState(null);
  const [lastFetchTime, setLastFetchTime] = useState(null);
  const updateIntervalRef = useRef(null);
  const timePeriodsQueueRef = useRef([]);

  // Fetch and organize data by time periods
  const fetchTollgateData = useCallback(async () => {
    try {
      const response = await fetch(`${API_GATEWAY_URL}/api/tollgate/traffic`);

      if (!response.ok) {
        console.warn('Tollgate API returned error:', response.status);
        setTollgates([]);
        return;
      }

      const data = await response.json();

      // Handle empty or null data
      if (!data || !Array.isArray(data) || data.length === 0) {
        setTollgates([]);
        return;
      }

      // Group data by time periods
      const timePeriods = {};
      data.forEach(tollgate => {
        if (!tollgate.trafficData || tollgate.trafficData.length === 0) return;

        // Sort traffic data by time (oldest first)
        const sortedTrafficData = [...tollgate.trafficData].sort((a, b) =>
          new Date(a.collectedAt) - new Date(b.collectedAt)
        );

        sortedTrafficData.forEach(dataPoint => {
          const timeKey = dataPoint.collectedAt;
          if (!timePeriods[timeKey]) {
            timePeriods[timeKey] = [];
          }
          timePeriods[timeKey].push({
            unitCode: tollgate.unitCode,
            unitName: tollgate.unitName,
            exDivName: tollgate.exDivName,
            dataPoint: dataPoint
          });
        });
      });

      // Sort time periods (oldest first)
      const sortedTimePeriods = Object.keys(timePeriods).sort();

      if (sortedTimePeriods.length === 0) return null;

      // Calculate cutoff: last time - 1 hour
      const latestTime = new Date(sortedTimePeriods[sortedTimePeriods.length - 1]);
      const oneHourAgo = new Date(latestTime.getTime() - 60 * 60 * 1000);

      // Split time periods: initial (3h ago ~ 1h ago) and sequential (1h ago ~ now)
      const initialPeriods = [];
      const sequentialPeriods = [];

      sortedTimePeriods.forEach(timeKey => {
        const timeDate = new Date(timeKey);
        if (timeDate < oneHourAgo) {
          initialPeriods.push(timeKey);
        } else {
          sequentialPeriods.push(timeKey);
        }
      });

      // Build initial tollgates with data
      const tollgateMap = {};

      // If we don't have enough initial periods data (less than 2 periods),
      // use all data immediately instead of sequential updates
      const periodsToShow = initialPeriods.length < 2 ? sortedTimePeriods : initialPeriods;

      periodsToShow.forEach(timeKey => {
        timePeriods[timeKey].forEach(item => {
          if (!tollgateMap[item.unitCode]) {
            tollgateMap[item.unitCode] = {
              unitCode: item.unitCode,
              unitName: item.unitName,
              exDivName: item.exDivName,
              trafficData: [],
              lastUpdated: null
            };
          }
          tollgateMap[item.unitCode].trafficData.push(item.dataPoint);
          tollgateMap[item.unitCode].lastUpdated = item.dataPoint.collectedAt;
        });
      });

      // Convert to array and sort traffic data (newest first for display)
      const initialTollgates = Object.values(tollgateMap).map(tg => ({
        ...tg,
        trafficData: tg.trafficData.sort((a, b) =>
          new Date(b.collectedAt) - new Date(a.collectedAt)
        )
      }));

      // Sort tollgates by latest traffic amount
      const sortedTollgates = initialTollgates.sort((a, b) => {
        const aAmount = a.trafficData.length > 0 ? a.trafficData[0].trafficAmount : 0;
        const bAmount = b.trafficData.length > 0 ? b.trafficData[0].trafficAmount : 0;
        return bAmount - aAmount;
      });

      setTollgates(sortedTollgates);
      setError(null);
      setLastFetchTime(new Date());

      // Store sequential periods for gradual updates
      // Only queue periods that weren't shown initially
      const periodsToQueue = initialPeriods.length < 2 ? [] : sequentialPeriods;
      timePeriodsQueueRef.current = periodsToQueue.map(timeKey => ({
        time: timeKey,
        data: timePeriods[timeKey]
      }));

      return {
        initialTollgates: sortedTollgates,
        sequentialPeriods: timePeriodsQueueRef.current
      };
    } catch (err) {
      console.error('Failed to fetch tollgate data:', err);
      setError(err.message);
      return null;
    }
  }, []);

  // Sequential update: Add one data point per tollgate over time
  const startSequentialUpdate = useCallback(() => {
    // Clear any existing interval
    if (updateIntervalRef.current) {
      clearInterval(updateIntervalRef.current);
    }

    const timePeriods = timePeriodsQueueRef.current;
    if (!timePeriods || timePeriods.length === 0) return;

    // Total updates = number of time periods × number of tollgates per period
    const totalUpdates = timePeriods.reduce((sum, period) => sum + period.data.length, 0);

    // Distribute updates over 60 minutes (or remaining time periods × 15 minutes)
    const totalDuration = 60 * 60 * 1000; // 60 minutes in ms
    const updateInterval = totalDuration / totalUpdates; // ~1.93 seconds per update

    // Flatten all updates into a single queue
    const updateQueue = [];
    timePeriods.forEach(period => {
      period.data.forEach(item => {
        updateQueue.push({
          unitCode: item.unitCode,
          dataPoint: item.dataPoint
        });
      });
    });

    let currentIndex = 0;

    // Process one update at a time
    updateIntervalRef.current = setInterval(() => {
      if (currentIndex >= updateQueue.length) {
        clearInterval(updateIntervalRef.current);
        updateIntervalRef.current = null;
        return;
      }

      const update = updateQueue[currentIndex];

      // Mark as loading
      setLoadingStates(prev => ({
        ...prev,
        [update.unitCode]: true
      }));

      // Update the specific tollgate by adding new data point
      setTimeout(() => {
        setTollgates(prevTollgates => {
          const newTollgates = prevTollgates.map(tg => {
            if (tg.unitCode === update.unitCode) {
              return {
                ...tg,
                trafficData: [update.dataPoint, ...tg.trafficData],
                lastUpdated: update.dataPoint.collectedAt
              };
            }
            return tg;
          });

          // Re-sort by latest traffic amount (newest data)
          return newTollgates.sort((a, b) => {
            const aAmount = a.trafficData && a.trafficData.length > 0 ? a.trafficData[0].trafficAmount : 0;
            const bAmount = b.trafficData && b.trafficData.length > 0 ? b.trafficData[0].trafficAmount : 0;
            return bAmount - aAmount;
          });
        });

        // Remove loading state
        setLoadingStates(prev => ({
          ...prev,
          [update.unitCode]: false
        }));
      }, 300);

      currentIndex++;
    }, updateInterval);
  }, []);

  // Initial load and start sequential updates
  useEffect(() => {
    const initializeData = async () => {
      const result = await fetchTollgateData();
      if (result && result.sequentialPeriods && result.sequentialPeriods.length > 0) {
        // Start sequential updates after showing initial state
        setTimeout(() => {
          startSequentialUpdate();
        }, 2000); // 2 second delay to show initial state
      }
    };

    initializeData();

    // Refresh every 60 minutes (after all sequential updates complete)
    const refreshTimer = setInterval(() => {
      initializeData();
    }, 60 * 60 * 1000); // 60 minutes

    return () => clearInterval(refreshTimer);
  }, [fetchTollgateData, startSequentialUpdate]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (updateIntervalRef.current) {
        clearInterval(updateIntervalRef.current);
      }
    };
  }, []);

  return (
    <div className="rounded-lg p-6">
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-white">요금소별 교통량</h2>
          <p className="text-sm text-slate-400 mt-1">
            15분 단위 실시간 교통량 모니터링
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
              <h3 className="text-sm font-medium text-red-800">
                데이터 수집 실패
              </h3>
              <div className="mt-1 text-sm text-red-700">
                <p>{error}</p>
                <p className="mt-1 text-xs">API 서버에 접속할 수 없거나 데이터가 아직 수집되지 않았습니다.</p>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Top 30 Traffic Chart */}
      {tollgates.length > 0 && (
        <div className="bg-slate-800/70 backdrop-blur-sm rounded-lg shadow-lg border border-slate-700 p-6 mb-6">
          <h3 className="text-lg font-semibold text-white mb-4">Top 30 통행량</h3>
          <div className="w-full">
            <div className="flex items-end justify-between gap-1 pb-2" style={{ height: '300px' }}>
              {tollgates.slice(0, 30).map((tollgate, index) => {
                const latestTraffic = tollgate.trafficData && tollgate.trafficData.length > 0
                  ? tollgate.trafficData[0].trafficAmount
                  : 0;
                const height = (latestTraffic / 1500) * 100;

                // Get color based on traffic amount
                const getBarColor = (amount) => {
                  if (amount >= 1200) return 'from-red-500 to-red-600';
                  if (amount >= 900) return 'from-orange-500 to-orange-600';
                  if (amount >= 600) return 'from-yellow-500 to-yellow-600';
                  if (amount >= 300) return 'from-green-500 to-green-600';
                  return 'from-blue-500 to-blue-600';
                };

                return (
                  <div key={tollgate.unitCode} className="flex flex-col items-center flex-1">
                    {/* Bar */}
                    <div className="w-full flex flex-col items-center justify-end" style={{ height: '250px' }}>
                      <div className="relative w-full bg-slate-700/50 rounded-t-sm flex flex-col justify-end"
                           style={{ height: '100%' }}>
                        <div
                          className={`bg-gradient-to-t ${getBarColor(latestTraffic)} w-full rounded-t-sm transition-all duration-500 flex items-start justify-center pt-1`}
                          style={{ height: `${Math.max(height, 2)}%` }}
                        >
                          {latestTraffic > 0 && (
                            <span className="text-xs font-medium text-white">
                              {latestTraffic}
                            </span>
                          )}
                        </div>
                      </div>
                    </div>
                    {/* Label */}
                    <div className="mt-2 text-center w-full overflow-hidden">
                      <div className="text-xs text-slate-500 mb-1">#{index + 1}</div>
                      <div className="text-xs font-medium text-slate-300 whitespace-nowrap transform -rotate-45 origin-center"
                           style={{ fontSize: '10px' }}>
                        {tollgate.unitName}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      )}

      {/* Tollgate Cards Grid - 5 columns */}
      {tollgates.length === 0 && !error ? (
        <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-5 gap-4">
          {[...Array(20)].map((_, i) => (
            <TollgateCard key={i} tollgate={null} isLoading={false} />
          ))}
        </div>
      ) : (
        <>
          <div className="mb-4 flex items-center justify-between">
            <p className="text-sm text-slate-400">
              총 <span className="font-semibold text-white">{tollgates.length}</span>개 요금소
            </p>
            <div className="flex items-center gap-2">
              <div className="flex items-center gap-1">
                <div className="w-2 h-2 rounded-full bg-blue-400 animate-pulse shadow-lg shadow-blue-400/50"></div>
                <span className="text-xs text-slate-400">순차 업데이트 중</span>
              </div>
            </div>
          </div>

          <div
            className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-5 gap-4"
            style={{
              transition: 'all 0.5s cubic-bezier(0.4, 0, 0.2, 1)'
            }}
          >
            {tollgates.map((tollgate) => (
              <div
                key={tollgate.unitCode}
                style={{
                  animation: 'fadeInSlide 0.4s ease-out',
                  transition: 'all 0.5s cubic-bezier(0.4, 0, 0.2, 1)'
                }}
              >
                <TollgateCard
                  tollgate={tollgate}
                  isLoading={loadingStates[tollgate.unitCode] || false}
                />
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
};

export default TollgateTrafficPanel;
