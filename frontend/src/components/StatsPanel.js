import React from 'react';

const StatsPanel = ({ stats }) => {
  if (!stats) return null;

  const statCards = [
    {
      title: '전체 사고',
      value: stats.totalAccidents || 0,
      icon: '📊',
      color: 'blue',
    },
    {
      title: '오늘 사고',
      value: stats.todayAccidents || 0,
      icon: '📅',
      color: 'green',
    },
  ];

  return (
    <div className="bg-slate-800/50 backdrop-blur-sm rounded-lg shadow-xl p-6 border border-slate-700">
      <h2 className="text-xl font-bold mb-4 flex items-center">
        <span className="mr-2">📈</span>
        통계
      </h2>

      {/* Stat Cards */}
      <div className="grid grid-cols-2 gap-4 mb-6">
        {statCards.map((card, idx) => (
          <div
            key={idx}
            className={`bg-${card.color}-900/20 border border-${card.color}-500/30 rounded-lg p-4 text-center`}
          >
            <div className="text-3xl mb-2">{card.icon}</div>
            <div className="text-sm text-slate-400 mb-1">{card.title}</div>
            <div className={`text-2xl font-bold text-${card.color}-400`}>
              {card.value.toLocaleString()}
            </div>
          </div>
        ))}
      </div>

      {/* By Type */}
      {stats.byType && Object.keys(stats.byType).length > 0 && (
        <div>
          <h3 className="font-bold mb-3 text-slate-300">사고 유형별</h3>
          <div className="space-y-2">
            {Object.entries(stats.byType).map(([type, count], idx) => {
              const total = stats.totalAccidents || 1;
              const percentage = ((count / total) * 100).toFixed(1);

              return (
                <div key={idx} className="bg-slate-700/30 rounded-lg p-3">
                  <div className="flex items-center justify-between mb-2">
                    <span className="text-sm font-medium">{type}</span>
                    <span className="text-sm text-slate-400">
                      {count}건 ({percentage}%)
                    </span>
                  </div>
                  <div className="w-full bg-slate-600 rounded-full h-2">
                    <div
                      className="bg-gradient-to-r from-blue-500 to-green-500 h-2 rounded-full transition-all duration-300"
                      style={{ width: `${percentage}%` }}
                    ></div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};

export default StatsPanel;
