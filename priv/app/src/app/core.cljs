(ns app.core
    (:require [reagent.core :as reagent :refer [atom]]
              [clojure.string :as str]
              [wscljs.client :as ws]
              [wscljs.format :as fmt]))

(enable-console-print!)
(println "Console ready")

(def wsurl (str "ws://" js/window.location.host "/ws/"))

(defonce current-question (atom "..."))
(defonce current-answer (atom "-"))
(defonce current-team (atom nil))
(defonce current-duds (atom []))
(defonce gating (atom false))

(defonce socket (atom nil))
(defonce ping-timer (atom nil))

;; Handler stuff

(defn decode-html [h]
  (let* [txt (. js/document createElement "textarea")]
    (do
     (set! (.-innerHTML txt) h)
     (.-value txt))))

(defn order-answers [question-type answers]
  (cond
   (= question-type "boolean") (sort answers)
   :else (->> answers shuffle shuffle)))

(defn on-question [{:keys [type :as qt question correct_answer incorrect_answers]}]
  (let* [answers (order-answers qt (conj incorrect_answers correct_answer))
         answer-fn (fn [i a] [:div {:key i}
                              (str (inc i) ". ")
                              (decode-html a)])]
    (reset! current-question (->> question decode-html))
    (reset! current-answer (map-indexed answer-fn answers))))

(defn parse-message-data [e]
 (->> e
      (.-data)
      (.parse js/JSON)
      (#(js->clj % :keywordize-keys true))))

(def message-handlers {
  "pong" #()
  "question" #(if-not (= (:question %1) nil)
                      (do (.log js/console "Updating question")
                          (on-question (:question %1))))
  "buzz" #(do (.log js/console "Updating current team")
              (reset! current-team (:team %1)))
  "duds" #(do (.log js/console "Updating duds")
              (reset! current-duds (:duds %1)))
  "clear" #(do (.log js/console "Clearing team and duds")
               (reset! current-team nil)
               (reset! current-duds []))
  "gating_started" #(do (.log js/console "Gate closed")
                        (reset! gating true))
  "gating_stopped" #(do (.log js/console "Gate opened")
                        (reset! gating false))
  })

(defn on-message [e]
  (let*
    [data (parse-message-data e)
     e-type (:type data)]
    ;(if-not (= e-type "pong") (prn "data" data)) ; debug all but pongs
    ((message-handlers e-type #(.log js/console "unexpected type:" e-type)) data)))

(defn on-open [e]
  (do
   (.log js/console "Opening a new connection:" e)
   (let* [ping-fn (fn [] (ws/send @socket "ping"))]
     (reset! ping-timer (js/setInterval ping-fn 5000)))))

(defn on-close [e]
  (do
   (.log js/console "Closing a connection:" e)
   (js/clearInterval @ping-timer)
   (reset! ping-timer nil)))

(def handlers {:on-message #(on-message %1)
               :on-open #(on-open %1)
               :on-close #(on-close %1)})

;; Connection

(defn socket-swap [old-socket new-socket]
  (do (if-not (= old-socket nil) (ws/close old-socket))
      new-socket))

;; React things

(defn app []
  [:div.center
   [:h3.question-marker "Q: " [:span.question @current-question]]
   [:h3.question-marker "A: " [:span.question @current-answer]]
   (if (= @current-team nil)
     [:h1.gate [:em (if @gating [:span.wait "WAIT"] [:span.press "PRESS"])]]
     [:h1 [:em "First: "] @current-team])
   (if-not (= @current-duds [])
     [:h1 (comment "Duds: ") (map-indexed (fn [i d] [:div {:key i} d]) @current-duds)])])

;; Press play!

(swap! socket socket-swap (ws/create wsurl handlers))
(reagent/render-component [app] (. js/document (getElementById "app")))

;;
;; Figwheel(?) meta stuff
;;

;(defn on-js-reload [] (js/clearInterval @ping-timer))

