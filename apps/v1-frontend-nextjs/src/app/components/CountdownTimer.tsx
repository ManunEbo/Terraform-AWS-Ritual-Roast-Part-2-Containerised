"use client";

import React, { useState, useEffect, useCallback } from "react";
import Image from "next/image";

interface CountdownUnitProps {
  value: string;
  label: string;
}

const CountdownUnit: React.FC<CountdownUnitProps> = ({ value, label }) => (
  <div
    className="relative w-20 h-20 sm:w-28 sm:h-28 lg:w-36 lg:h-36 flex flex-col justify-center items-center bg-contain bg-no-repeat bg-center transition-transform hover:scale-105"
    style={{ backgroundImage: "url('/images/count-bg.png')" }}
  >
    <span className="text-xl sm:text-2xl lg:text-4xl font-bold" style={{ color: "var(--brown)" }}>
      {value}
    </span>
    <span className="text-xs sm:text-sm lg:text-base mt-1 font-bold" style={{ color: "var(--brown-dark)" }}>
      {label}
    </span>
  </div>
);

interface TimeLeft {
  days: number;
  hours: number;
  minutes: number;
  seconds: number;
}

const CountdownTimer = () => {
  // 1. READ THE DEPLOYMENT LOCK: 
  // Fetch the date that was permanently baked in during the Docker build.
  const [targetDate] = useState(() => {
    const deploymentDate = process.env.NEXT_PUBLIC_CONTEST_DEADLINE;
    
    if (deploymentDate) {
      return new Date(deploymentDate);
    }
    
    // Developer Fallback (just in case you run the app locally without rebuilding)
    const fallback = new Date();
    fallback.setMonth(fallback.getMonth() + 3);
    return fallback;
  });

  const [timeLeft, setTimeLeft] = useState<TimeLeft>({
    days: 0,
    hours: 0,
    minutes: 0,
    seconds: 0,
  });

  const [isAnimated, setIsAnimated] = useState(false);
  const [isMounted, setIsMounted] = useState(false);

  const calculateTimeLeft = useCallback((): TimeLeft => {
    const difference = +targetDate - +new Date();
    if (difference > 0) {
      return {
        days: Math.floor(difference / (1000 * 60 * 60 * 24)),
        hours: Math.floor((difference / (1000 * 60 * 60)) % 24),
        minutes: Math.floor((difference / 1000 / 60) % 60),
        seconds: Math.floor((difference / 1000) % 60),
      };
    }
    return { days: 0, hours: 0, minutes: 0, seconds: 0 };
  }, [targetDate]);

  useEffect(() => {
    // 2. HYDRATION SHIELD: Signal that we are now on the client
    setIsMounted(true);
    setTimeLeft(calculateTimeLeft());

    const timer = setInterval(() => {
      setTimeLeft(calculateTimeLeft());
    }, 1000);

    const animationTimeout = setTimeout(() => {
      setIsAnimated(true);
    }, 100);

    return () => {
      clearInterval(timer);
      clearTimeout(animationTimeout);
    };
  }, [calculateTimeLeft]);

  // 3. PREVENT HYDRATION MISMATCH
  if (!isMounted) {
    return <div className="w-full py-12 md:py-20 h-[400px]" />;
  }

  return (
    <div
      className="relative w-full py-12 md:py-20 text-center bg-cover bg-center overflow-hidden"
      style={{
        backgroundImage: "url('/images/bg-enter-the-contest.png')",
        fontFamily: "var(--font-montserrat-alternates)",
      }}
    >
      <div
        className={`absolute -left-10 md:-left-20 bottom-0 z-10 transition-all duration-1000 ease-out opacity-20 lg:opacity-80 ${
          isAnimated ? "translate-x-0" : "-translate-x-full"
        }`}
      >
        <Image
          src="/images/left-cho-enter-the-contest.png"
          alt="Chocolate treats"
          width={350}
          height={350}
          style={{ objectFit: "contain" }}
        />
      </div>

      <div
        className={`hidden sm:block absolute right-4 md:right-16 bottom-8 z-10 transition-all duration-1000 ease-out opacity-20 lg:opacity-80 ${
          isAnimated ? "translate-x-0" : "translate-x-full"
        }`}
      >
        <Image
          src="/images/right-enter-the-contest.png"
          alt="Chocolate chip cookie"
          width={250}
          height={250}
          style={{ objectFit: "contain" }}
        />
      </div>

      <div className="relative z-20 px-4">
        <h2 className="text-2xl md:text-3xl font-bold" style={{ color: "var(--brown)" }}>
          Enter the Contest
        </h2>
        <p
          className="mt-3 text-sm md:text-base font-semibold max-w-2xl mx-auto"
          style={{ color: "var(--brown-dark)" }}
        >
          Submit your favorite recipe, and it might be listed on our website! Winner gets featured on our blog!
        </p>

        <div className="flex flex-wrap justify-center items-center gap-2 sm:gap-4 md:gap-8 mt-8 md:mt-12">
          <CountdownUnit value={String(timeLeft.days).padStart(2, "0")} label="Days" />
          <CountdownUnit value={String(timeLeft.hours).padStart(2, "0")} label="Hours" />
          <CountdownUnit value={String(timeLeft.minutes).padStart(2, "0")} label="Minutes" />
          <CountdownUnit value={String(timeLeft.seconds).padStart(2, "0")} label="Seconds" />
        </div>
      </div>

      <div
        className="absolute bottom-0 left-0 w-full border-b-4 border-dotted"
        style={{ borderColor: "var(--gold)" }}
      ></div>
    </div>
  );
};

export default CountdownTimer;