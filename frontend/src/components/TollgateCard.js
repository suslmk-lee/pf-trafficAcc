import React from 'react';

const TollgateCard = ({ tollgate, isLoading }) => {
  if (!tollgate) {
    return (
      <div className="bg-slate-800/70 backdrop-blur-sm rounded-lg shadow-lg p-4 border border-slate-700">
        <div className="animate-pulse">
          <div className="h-4 bg-slate-700 rounded w-3/4 mb-2"></div>
          <div className="h-3 bg-slate-700 rounded w-1/2 mb-4"></div>
          <div className="space-y-2">
            <div className="h-6 bg-slate-700 rounded"></div>
            <div className="h-6 bg-slate-700 rounded"></div>
            <div className="h-6 bg-slate-700 rounded"></div>
          </div>
        </div>
      </div>
    );
  }

  const { unitName, exDivName, trafficData } = tollgate;

  // Sort traffic data by time (newest first for display)
  const sortedData = [...(trafficData || [])].sort((a, b) =>
    new Date(b.collectedAt) - new Date(a.collectedAt)
  );

  // Use fixed max value of 1500 for consistent bar scaling across all cards
  const maxTraffic = 1500;

  // Format time for display
  // Note: API returns Korea time but in UTC format (Z suffix)
  // We need to parse it without timezone conversion
  const formatTime = (dateStr) => {
    // Extract time from ISO string (ignore timezone)
    const timePart = dateStr.split('T')[1].substring(0, 5); // "HH:MM"
    return timePart;
  };

  // Get badge color based on exDivName
  const getBadgeColor = (exDivName) => {
    if (exDivName === '도공') return 'bg-blue-900/50 text-blue-300 border border-blue-700';
    return 'bg-purple-900/50 text-purple-300 border border-purple-700';
  };

  // Get bar color based on traffic amount
  const getBarColor = (amount) => {
    if (amount >= 1200) return 'from-red-500 to-red-600';
    if (amount >= 900) return 'from-orange-500 to-orange-600';
    if (amount >= 600) return 'from-yellow-500 to-yellow-600';
    if (amount >= 300) return 'from-green-500 to-green-600';
    return 'from-blue-500 to-blue-600';
  };

  return (
    <div className={`bg-slate-800/70 backdrop-blur-sm rounded-lg shadow-lg border border-slate-700 p-4 transition-all duration-300 hover:border-slate-600 ${
      isLoading ? 'ring-2 ring-blue-500 ring-opacity-50 shadow-blue-500/20' : ''
    }`}>
      {/* Header */}
      <div className="mb-3">
        <div className="flex items-center justify-between">
          <h3 className="font-semibold text-white text-sm">{unitName}</h3>
          <span className={`text-xs px-2 py-1 rounded-full ${getBadgeColor(exDivName)}`}>
            {exDivName}
          </span>
        </div>
      </div>

      {/* Traffic Graph */}
      <div className="space-y-1.5">
        {sortedData.length === 0 ? (
          <div className="text-center py-4 text-slate-500 text-xs">
            데이터 없음
          </div>
        ) : (
          sortedData.slice(0, 12).map((data, index) => {
            const width = (data.trafficAmount / maxTraffic) * 100;
            const barColorClass = getBarColor(data.trafficAmount);
            const showNumberOutside = data.trafficAmount <= 300;

            return (
              <div key={index} className="flex items-center gap-2">
                {/* Time label */}
                <div className="text-xs text-slate-400 w-12 text-right flex-shrink-0">
                  {formatTime(data.collectedAt)}
                </div>

                {/* Bar container */}
                <div className="flex-1 bg-slate-700/50 rounded-sm h-5 relative">
                  <div
                    className={`bg-gradient-to-r ${barColorClass} h-full rounded-sm transition-all duration-500 flex items-center justify-end pr-2`}
                    style={{ width: `${Math.max(width, 2)}%` }}
                  >
                    {data.trafficAmount > 0 && !showNumberOutside && (
                      <span className="text-xs text-white font-medium">
                        {data.trafficAmount}
                      </span>
                    )}
                  </div>
                  {/* Number displayed on gray area (right of the colored bar) for values <= 300 */}
                  {showNumberOutside && data.trafficAmount > 0 && (
                    <span
                      className="absolute top-0 h-full flex items-center text-xs text-slate-300 font-medium pl-2"
                      style={{ left: `${Math.max(width, 2)}%` }}
                    >
                      {data.trafficAmount}
                    </span>
                  )}
                </div>
              </div>
            );
          })
        )}
      </div>

      {/* Last Updated */}
      {tollgate.lastUpdated && (
        <div className="mt-2 pt-2 border-t border-slate-700">
          <p className="text-xs text-slate-500 text-right">
            최근 수집: {formatTime(tollgate.lastUpdated)}
          </p>
        </div>
      )}
    </div>
  );
};

export default TollgateCard;
