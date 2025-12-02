import React, { useState, useEffect } from 'react';

const ClusterStatus = () => {
  const [currentTime, setCurrentTime] = useState(new Date());

  useEffect(() => {
    const interval = setInterval(() => {
      setCurrentTime(new Date());
    }, 1000);

    return () => clearInterval(interval);
  }, []);

  // Simulated cluster health (in production, this would come from actual health checks)
  const clusters = [
    {
      name: 'Naver Cloud',
      status: 'healthy',
      color: 'naver',
      region: 'KR-Seoul-1',
      pods: '4/4',
      cpu: '45%',
      memory: '62%',
    },
    {
      name: 'NHN Cloud',
      status: 'healthy',
      color: 'nhn',
      region: 'KR-Seoul-2',
      pods: '4/4',
      cpu: '38%',
      memory: '58%',
    },
  ];

  const getStatusBadge = (status) => {
    switch (status) {
      case 'healthy':
        return (
          <span className="flex items-center text-green-400">
            <span className="w-2 h-2 bg-green-400 rounded-full mr-2 animate-pulse"></span>
            운영중
          </span>
        );
      case 'degraded':
        return (
          <span className="flex items-center text-yellow-400">
            <span className="w-2 h-2 bg-yellow-400 rounded-full mr-2 animate-pulse"></span>
            경고
          </span>
        );
      case 'down':
        return (
          <span className="flex items-center text-red-400">
            <span className="w-2 h-2 bg-red-400 rounded-full mr-2"></span>
            중단
          </span>
        );
      default:
        return null;
    }
  };

  return (
    <div className="bg-slate-800/50 backdrop-blur-sm rounded-lg shadow-xl p-6 border border-slate-700">
      <h2 className="text-xl font-bold mb-4 flex items-center">
        <span className="mr-2">☁️</span>
        클러스터 상태
      </h2>

      {/* Current Time */}
      <div className="mb-6 text-center bg-slate-700/30 p-3 rounded-lg">
        <div className="text-sm text-slate-400 mb-1">시스템 시간</div>
        <div className="text-2xl font-mono font-bold text-green-400">
          {currentTime.toLocaleTimeString('ko-KR')}
        </div>
      </div>

      {/* Cluster Cards */}
      <div className="space-y-4">
        {clusters.map((cluster, idx) => (
          <div
            key={idx}
            className="bg-slate-700/30 rounded-lg p-4 border border-slate-600 hover:border-slate-500 transition-all"
          >
            <div className="flex items-center justify-between mb-3">
              <div>
                <h3 className={`font-bold text-${cluster.color}`}>
                  {cluster.name}
                </h3>
                <p className="text-xs text-slate-400">{cluster.region}</p>
              </div>
              <div className="text-sm">{getStatusBadge(cluster.status)}</div>
            </div>

            <div className="grid grid-cols-3 gap-2 text-xs">
              <div className="bg-slate-800/50 p-2 rounded">
                <div className="text-slate-400">Pods</div>
                <div className="font-bold text-green-400">{cluster.pods}</div>
              </div>
              <div className="bg-slate-800/50 p-2 rounded">
                <div className="text-slate-400">CPU</div>
                <div className="font-bold text-blue-400">{cluster.cpu}</div>
              </div>
              <div className="bg-slate-800/50 p-2 rounded">
                <div className="text-slate-400">Memory</div>
                <div className="font-bold text-purple-400">{cluster.memory}</div>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Architecture Info */}
      <div className="mt-6 p-4 bg-blue-900/20 border border-blue-500/30 rounded-lg">
        <h4 className="font-bold text-blue-300 mb-2 text-sm">🏗️ 아키텍처</h4>
        <ul className="text-xs text-slate-300 space-y-1">
          <li>• Active-Active 이중화</li>
          <li>• Karmada 멀티클러스터</li>
          <li>• Istio Service Mesh</li>
          <li>• Redis Stream 파이프라인</li>
          <li>• MariaDB 중앙 DB</li>
        </ul>
      </div>

      {/* Failover Indicator */}
      <div className="mt-4 text-center">
        <div className="inline-block bg-green-900/20 border border-green-500/30 px-4 py-2 rounded-full">
          <span className="text-xs text-green-300">
            ✓ 자동 페일오버 활성화
          </span>
        </div>
      </div>
    </div>
  );
};

export default ClusterStatus;
