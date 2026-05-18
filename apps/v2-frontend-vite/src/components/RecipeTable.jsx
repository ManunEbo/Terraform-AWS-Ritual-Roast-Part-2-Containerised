import React from "react";

const RecipeTable = ({ initialRecipes }) => {
  if (!initialRecipes || initialRecipes.length === 0) {
    return (
      <div className="w-full text-center py-8">
        <div className="max-w-md mx-auto bg-[#1A1A1A] border border-[#333] rounded-lg p-6 shadow-[0_0_15px_rgba(50,205,50,0.05)]">
          <h3 className="text-lg font-semibold text-[#32CD32] mb-2">Datastore Empty</h3>
          <p className="text-sm text-gray-400">Awaiting initial telemetry.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="w-full max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <h2 className="text-2xl font-bold text-[#32CD32] mb-6 font-['Montserrat_Alternates']">Telemetry Log</h2>
      <div className="overflow-x-auto shadow-lg rounded-lg border border-[#333]">
        <table className="min-w-full bg-[#121212] border-collapse">
          <thead className="bg-[#0a0a0a] text-[#32CD32] text-sm tracking-wider">
            <tr>
              <th className="py-4 px-6 text-left font-semibold border-b border-[#333]">CHEF</th>
              <th className="py-4 px-6 text-left font-semibold border-b border-[#333]">DESIGNATION</th>
              <th className="py-4 px-6 text-left font-semibold border-b border-[#333]">COMPONENTS</th>
              <th className="py-4 px-6 text-left font-semibold border-b border-[#333]">PROTOCOL</th>
            </tr>
          </thead>
          <tbody>
            {initialRecipes.map((item, index) => (
              <tr key={item.id || `recipe-${index}`} className="border-b border-[#222] bg-[#1A1A1A] hover:bg-[#242424] transition-colors text-gray-300">
                <td className="py-4 px-6 font-semibold text-white whitespace-nowrap">{item.name}</td>
                <td className="py-4 px-6 text-[#32CD32] font-semibold">{item.recipe_name}</td>
                <td className="py-4 px-6 text-xs leading-relaxed"><div className="break-words">{item.ingredients}</div></td>
                <td className="py-4 px-6 text-xs leading-relaxed"><div className="break-words">{item.recipe_details}</div></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
};

export default RecipeTable;
